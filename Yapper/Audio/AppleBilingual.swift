import AVFoundation
import Foundation
import Speech

/// Two languages with Apple's on-device model, which listens for one at a
/// time: every language's model hears the dictation, and `Bilingual` works
/// out which one heard each part right. Apple's models are quick (a tenth
/// of a second or so per pass), so the extra passes cost little.
@available(iOS 26.0, macOS 26.0, *)
enum AppleBilingual {
    /// Whether a dictation can listen in two languages, and if not, why.
    enum Availability: Equatable {
        /// This device's language and the second language, in that order.
        case ready([Locale])
        /// No second language in Settings.
        case off
        /// A second language is set but can't be used; the reason, in words.
        case unavailable(String)
    }

    static func availability() async -> Availability {
        guard let id = Settings.secondLanguage else { return .off }
        let secondName = AppleAnalyzer.name(Locale(identifier: id))
        guard let primary = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            return .unavailable("Second language not used: Apple's newer model doesn't support this \(Device.name)'s language (\(Locale.current.identifier)).")
        }
        guard let second = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
            return .unavailable("Second language not used: Apple's newer model doesn't support \(secondName).")
        }
        guard primary.language.languageCode != second.language.languageCode else {
            return .unavailable("Second language not used: \(secondName) is the same language as this \(Device.name)'s.")
        }
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        guard installed.contains(primary.identifier(.bcp47)) else {
            return .unavailable("Second language not used: Apple's newer model for \(AppleAnalyzer.name(primary)) isn't on this \(Device.name) yet (Settings › Speech model).")
        }
        guard installed.contains(second.identifier(.bcp47)) else {
            return .unavailable("Second language not used: \(secondName)'s model isn't on this \(Device.name) yet. Get it in Settings › Languages.")
        }
        return .ready([primary, second])
    }

    /// This device's language and the second language from Settings, when
    /// both can be used. Nil means dictate in one language as usual.
    static func languages() async -> [Locale]? {
        if case let .ready(locales) = await availability() { return locales }
        return nil
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

    /// The text, and how it was split, for History.
    static func transcribe(_ samples: [Float], sampleRate: Double,
                           prepared: Prepared) async throws -> (text: String, breakdown: LanguageBreakdown) {
        let locales = prepared.locales
        let ids = locales.map { $0.identifier(.bcp47) }
        let duration = Double(samples.count) / sampleRate
        var passes = 1
        let first = try await words(samples, sampleRate: sampleRate, session: prepared)
        let codes = locales.map { $0.language.languageCode?.identifier ?? $0.identifier }
        // What each language's model made of the whole dictation alone, for
        // History's details.
        let heard = first.indices.map {
            LanguageBreakdown.Part(language: ids[$0], start: 0, end: duration, text: text(first[$0]),
                                   confidence: Bilingual.meanConfidence(first[$0]))
        }

        func whole(_ language: Int, method: LanguageBreakdown.Method, keptWhole: Bool = false) -> (String, LanguageBreakdown) {
            let words = first[language]
            let part = LanguageBreakdown.Part(language: ids[language], start: 0, end: duration, text: text(words),
                                              confidence: Bilingual.meanConfidence(words))
            return (part.text, LanguageBreakdown(languages: ids, method: method, parts: [part], passes: passes,
                                                 keptWhole: keptWhole ? ids[language] : nil, heard: heard))
        }

        switch Bilingual.strategy(codes[0], codes[1]) {
        case .windows:
            let best = first.indices.max { Bilingual.meanConfidence(first[$0]) < Bilingual.meanConfidence(first[$1]) } ?? 0
            let cuts = Bilingual.windowCuts(first, duration: duration)
            guard !cuts.isEmpty else { return whole(best, method: .windows) }

            // Each window's language, from both models hearing just it.
            let bounds = [0] + cuts + [duration]
            var languages: [Int] = []
            for index in 0..<(bounds.count - 1) {
                let heard = try await piece(samples, sampleRate: sampleRate, start: bounds[index], end: bounds[index + 1],
                                            padding: Bilingual.windowPadding, duration: duration, locales: locales,
                                            isFirst: index == 0, isLast: index == bounds.count - 2)
                passes += 1
                languages.append(Bilingual.language(of: heard, previous: languages.last))
            }
            let regions = Bilingual.regions(cuts: cuts, languages: languages, duration: duration)
            guard regions.count > 1 else { return whole(regions.first?.language ?? best, method: .windows) }

            // Each region in its own language.
            var parts: [LanguageBreakdown.Part] = []
            var result: [Bilingual.Word] = []
            for (index, region) in regions.enumerated() {
                let heard = try await piece(samples, sampleRate: sampleRate, start: region.start, end: region.end,
                                            padding: Bilingual.windowPadding, duration: duration,
                                            locales: [locales[region.language]],
                                            isFirst: index == 0, isLast: index == regions.count - 1)[0]
                passes += 1
                result += heard
                parts.append(LanguageBreakdown.Part(language: ids[region.language], start: region.start, end: region.end,
                                                    text: text(heard), confidence: Bilingual.meanConfidence(heard)))
            }
            // Keep the split only when the models are surer of it than of
            // the best single language: a dictation in one language with a
            // borrowed word or two reads better left whole.
            guard Bilingual.meanConfidence(result) > Bilingual.meanConfidence(first[best]) else {
                return whole(best, method: .windows, keptWhole: true)
            }
            return (text(result), LanguageBreakdown(languages: ids, method: .windows, parts: parts, passes: passes, keptWhole: nil, heard: heard))

        case let .script(base):
            let words = first[base]
            let other = 1 - base
            var pieces: [String] = []
            var parts: [LanguageBreakdown.Part] = []
            func add(_ language: Int, _ words: [Bilingual.Word], as piece: String) {
                guard let firstWord = words.first, let lastWord = words.last else { return }
                pieces.append(piece)
                let part = LanguageBreakdown.Part(language: ids[language], start: firstWord.start, end: lastWord.end,
                                                  text: Bilingual.join([piece]), confidence: Bilingual.meanConfidence(words))
                if let last = parts.last, last.language == part.language {
                    parts[parts.count - 1].end = part.end
                    parts[parts.count - 1].text = Bilingual.join([last.text, piece])
                } else {
                    parts.append(part)
                }
            }
            var next = 0
            for span in Bilingual.latinSpans(words) {
                let before = Array(words[next..<span.lowerBound])
                add(base, before, as: before.map(\.text).joined())
                let own = Array(words[span])
                let redo = try await piece(samples, sampleRate: sampleRate, start: own[0].start, end: own[own.count - 1].end,
                                           padding: Bilingual.spanPadding, duration: duration, locales: [locales[other]],
                                           isFirst: false, isLast: false)[0]
                passes += 1
                if Bilingual.shouldSplice(own: own, redo: redo) {
                    add(other, redo, as: Bilingual.spliced(text(redo)))
                } else {
                    // The base model's own spelling stays, but it's still the
                    // other language being spoken.
                    add(other, own, as: own.map(\.text).joined())
                }
                next = span.upperBound + 1
            }
            let rest = Array(words[next...])
            add(base, rest, as: rest.map(\.text).joined())
            return (Bilingual.join(pieces), LanguageBreakdown(languages: ids, method: .script, parts: parts, passes: passes, keptWhole: nil, heard: heard))
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
