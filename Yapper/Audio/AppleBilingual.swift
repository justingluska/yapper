import AVFoundation
import Foundation
import Speech

/// Two languages with Apple's on-device model, which listens for one at a
/// time: every language's model hears the dictation, and `Bilingual` works
/// out which one heard each part right. Apple's models are quick (a tenth
/// of a second or so per pass), so the extra passes cost little.
@available(iOS 26.0, macOS 26.0, *)
enum AppleBilingual {
    /// This device's language and the second language from Settings, when
    /// one is set, differs, and both models are on the device. Nil means
    /// dictate in one language as usual.
    static func languages() async -> [Locale]? {
        guard let id = Settings.secondLanguage,
              let primary = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current),
              let second = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)),
              primary.language.languageCode != second.language.languageCode
        else { return nil }
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        guard installed.contains(primary.identifier(.bcp47)), installed.contains(second.identifier(.bcp47))
        else { return nil }
        return [primary, second]
    }

    /// Both models started, ready for one recording's first pass.
    final class Prepared {
        let locales: [Locale]
        let transcribers: [SpeechTranscriber]
        let analyzer: SpeechAnalyzer
        let format: AVAudioFormat

        init(locales: [Locale], transcribers: [SpeechTranscriber], analyzer: SpeechAnalyzer, format: AVAudioFormat) {
            self.locales = locales
            self.transcribers = transcribers
            self.analyzer = analyzer
            self.format = format
        }
    }

    /// One analyzer running every language's model on the same audio.
    /// Models linger after use, so the passes after the first start warm.
    static func prepare(_ locales: [Locale]) async throws -> Prepared {
        for locale in locales {
            // The models must be reserved for Yapper to use them; this is a
            // no-op when they already are.
            try await AssetInventory.reserve(locale: locale)
        }
        let transcribers = locales.map(makeTranscriber)
        let analyzer = SpeechAnalyzer(modules: transcribers,
                                      options: .init(priority: .userInitiated, modelRetention: .lingering))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: transcribers) else {
            throw AppleAnalyzer.AnalyzerError.audioFormat
        }
        try await analyzer.prepareToAnalyze(in: format)
        return Prepared(locales: locales, transcribers: transcribers, analyzer: analyzer, format: format)
    }

    static func transcribe(_ samples: [Float], sampleRate: Double, prepared: Prepared) async throws -> String {
        let locales = prepared.locales
        let duration = Double(samples.count) / sampleRate
        let first = try await words(samples, sampleRate: sampleRate, session: prepared)
        let codes = locales.map { $0.language.languageCode?.identifier ?? $0.identifier }

        switch Bilingual.strategy(codes[0], codes[1]) {
        case .windows:
            let single = first.max { Bilingual.meanConfidence($0) < Bilingual.meanConfidence($1) } ?? []
            let cuts = Bilingual.windowCuts(first, duration: duration)
            guard !cuts.isEmpty else { return text(single) }

            // Each window's language, from both models hearing just it.
            let bounds = [0] + cuts + [duration]
            var languages: [Int] = []
            for index in 0..<(bounds.count - 1) {
                let heard = try await piece(samples, sampleRate: sampleRate, start: bounds[index], end: bounds[index + 1],
                                            padding: Bilingual.windowPadding, duration: duration, locales: locales,
                                            isFirst: index == 0, isLast: index == bounds.count - 2)
                languages.append(Bilingual.language(of: heard, previous: languages.last))
            }
            let regions = Bilingual.regions(cuts: cuts, languages: languages, duration: duration)
            guard regions.count > 1 else { return text(first[regions.first?.language ?? 0]) }

            // Each region in its own language.
            var result: [Bilingual.Word] = []
            for (index, region) in regions.enumerated() {
                let heard = try await piece(samples, sampleRate: sampleRate, start: region.start, end: region.end,
                                            padding: Bilingual.windowPadding, duration: duration,
                                            locales: [locales[region.language]],
                                            isFirst: index == 0, isLast: index == regions.count - 1)
                result += heard[0]
            }
            // Keep the split only when the models are surer of it than of
            // the best single language: a dictation in one language with a
            // borrowed word or two reads better left whole.
            return Bilingual.meanConfidence(result) > Bilingual.meanConfidence(single) ? text(result) : text(single)

        case let .script(base):
            let words = first[base]
            let other = locales[1 - base]
            var pieces: [String] = []
            var next = 0
            for span in Bilingual.latinSpans(words) {
                pieces += words[next..<span.lowerBound].map(\.text)
                let own = Array(words[span])
                let redo = try await piece(samples, sampleRate: sampleRate, start: own[0].start, end: own[own.count - 1].end,
                                           padding: Bilingual.spanPadding, duration: duration, locales: [other],
                                           isFirst: false, isLast: false)[0]
                pieces.append(Bilingual.shouldSplice(own: own, redo: redo) ? " \(text(redo)) " : own.map(\.text).joined())
                next = span.upperBound + 1
            }
            pieces += words[next...].map(\.text)
            return Bilingual.join(pieces)
        }
    }

    /// The words of one piece of the dictation, from each of `locales`.
    private static func piece(_ samples: [Float], sampleRate: Double, start: Double, end: Double, padding: Double,
                              duration: Double, locales: [Locale], isFirst: Bool, isLast: Bool) async throws -> [[Bilingual.Word]] {
        let range = Bilingual.padded(start: start, end: end, by: padding, duration: duration)
        let from = min(samples.count, Int(range.lowerBound * sampleRate))
        let to = min(samples.count, Int(range.upperBound * sampleRate))
        guard to > from else { return locales.map { _ in [] } }
        let session = try await prepare(locales)
        let heard = try await words(Array(samples[from..<to]), sampleRate: sampleRate, session: session)
        return heard.map {
            Bilingual.inside($0, offset: range.lowerBound, start: start, end: end, isFirst: isFirst, isLast: isLast)
        }
    }

    /// Runs the analyzer over the samples and returns each model's words.
    private static func words(_ samples: [Float], sampleRate: Double, session: Prepared) async throws -> [[Bilingual.Word]] {
        guard let source = AppleAnalyzer.buffer(samples, sampleRate: sampleRate),
              let audio = AppleAnalyzer.convert(source, to: session.format)
        else { throw AppleAnalyzer.AnalyzerError.audioFormat }

        let collectors = session.transcribers.map { transcriber in
            Task {
                var words: [Bilingual.Word] = []
                for try await result in transcriber.results where result.isFinal {
                    words += Self.words(in: result.text)
                }
                return words
            }
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        input.yield(AnalyzerInput(buffer: audio))
        input.finish()
        if let end = try await session.analyzer.analyzeSequence(stream) {
            try await session.analyzer.finalizeAndFinish(through: end)
        } else {
            await session.analyzer.cancelAndFinishNow()
        }
        var heard: [[Bilingual.Word]] = []
        for collector in collectors {
            heard.append(try await collector.value)
        }
        return heard
    }

    /// A result's text as words: each run of the attributed text is a word
    /// with its time and confidence. Runs with no time (rare) are skipped.
    private static func words(in text: AttributedString) -> [Bilingual.Word] {
        text.runs.compactMap { run in
            guard let range = run.audioTimeRange else { return nil }
            let string = String(text[run.range].characters)
            guard !string.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Bilingual.Word(text: string, start: range.start.seconds, end: range.end.seconds,
                                  confidence: run.transcriptionConfidence ?? 0)
        }
    }

    private static func text(_ words: [Bilingual.Word]) -> String {
        Bilingual.join(words.map(\.text))
    }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                          attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    }
}
