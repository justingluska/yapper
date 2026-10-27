import Foundation

/// Dictating in two languages, switching back and forth even mid-sentence,
/// with Apple's speech model, which only ever listens for one language.
///
/// Each language's model gets the parts in its own language right and
/// mangles or drops the rest, so Yapper finds where the speech switches and
/// transcribes each part with the model for its language. Two ways to find
/// the switches, measured on real code-switched speech (Bangor Miami
/// Spanish–English, ASCEND Mandarin–English, MCE Cantonese–English,
/// CS-FLEURS):
///
/// - Same script (English and Spanish, French, German…): cut the dictation
///   at word gaps into short windows, take each window's language from which
///   model is more confident, then transcribe each run of same-language
///   windows in its language. Natural Spanglish went from 36% of words wrong
///   with one language to 20%.
/// - Different scripts (English and Chinese, Japanese, Korean…): the
///   non-Latin model writes the English it hears in Latin letters, misspelt.
///   Those stretches go through the English model again and replace the
///   misspelt text when English is at least as sure. Mandarin–English went
///   from 28% wrong to 20%.
///
/// This file is the arithmetic only, so it's testable without audio;
/// `AppleAnalyzer.transcribeBilingual` runs the models.
enum Bilingual {
    /// A word as a model heard it: its text (with the model's spacing and
    /// punctuation), where it is in the audio, in seconds, and how sure the
    /// model is, 0...1.
    struct Word: Equatable {
        var text: String
        var start: Double
        var end: Double
        var confidence: Double

        var middle: Double { (start + end) / 2 }
    }

    /// A stretch of the dictation in one language, `language` being an
    /// index into the languages transcribed.
    struct Region: Equatable {
        var start: Double
        var end: Double
        var language: Int
    }

    enum Strategy: Equatable {
        /// Both languages share a script: find the switches by confidence.
        case windows
        /// Only `base` (an index) uses a non-Latin script: transcribe with
        /// it, and redo its Latin-letter stretches with the other language.
        case script(base: Int)
    }

    /// Windows aim for this length: shorter ones are too little speech for
    /// a model to be sure of its language, longer ones miss short switches.
    static let windowLength = 1.4
    /// Preference for staying in the window before's language, so one
    /// unsure window doesn't flip the language mid-phrase.
    static let stayBonus = 0.05
    /// Audio kept either side of a piece, so words at its edges aren't cut
    /// in half. Only words whose middle falls inside the piece count.
    static let windowPadding = 0.4
    static let spanPadding = 0.15
    /// Latin stretches closer than this, with only punctuation between,
    /// are one stretch.
    static let spanJoin = 0.4
    /// The English redo of a Latin stretch replaces it only when it's at
    /// least this sure, and no more than `spliceMargin` less sure than the
    /// base model was of its own letters.
    static let spliceMinimum = 0.4
    static let spliceMargin = 0.05

    /// Languages whose models write in Latin letters. Everything else
    /// (Chinese, Cantonese, Japanese, Korean…) writes in its own script.
    private static let latinLanguages: Set<String> = [
        "en", "es", "fr", "de", "it", "pt", "nl", "ca", "da", "sv", "nb", "no", "fi",
        "pl", "cs", "sk", "hr", "ro", "hu", "tr", "id", "ms", "vi",
    ]

    static func usesLatinScript(_ languageCode: String) -> Bool {
        latinLanguages.contains(languageCode.lowercased())
    }

    /// How to split a dictation in these two languages (language codes).
    static func strategy(_ first: String, _ second: String) -> Strategy {
        switch (usesLatinScript(first), usesLatinScript(second)) {
        case (true, false): return .script(base: 1)
        case (false, true): return .script(base: 0)
        default: return .windows
        }
    }

    static func meanConfidence(_ words: [Word]) -> Double {
        guard !words.isEmpty else { return 0 }
        return words.map(\.confidence).reduce(0, +) / Double(words.count)
    }

    // MARK: Windows

    /// Where to cut a dictation into windows: in the gaps between words
    /// (any language's), about `length` apart, with no short window at the end.
    static func windowCuts(_ transcripts: [[Word]], duration: Double, length: Double = windowLength) -> [Double] {
        var gaps: [Double] = []
        for words in transcripts {
            for (a, b) in zip(words, words.dropFirst()) {
                gaps.append((a.end + b.start) / 2)
            }
        }
        var cuts: [Double] = []
        var last = 0.0
        for gap in gaps.sorted() where gap - last >= length && duration - gap >= length * 0.6 {
            cuts.append(gap)
            last = gap
        }
        return cuts
    }

    /// Which language a window is in: the one whose model is most sure of
    /// what it heard, with a small bonus for the window before's language.
    static func language(of transcripts: [[Word]], previous: Int?) -> Int {
        var best = 0
        var bestScore = -Double.infinity
        for (index, words) in transcripts.enumerated() {
            let score = meanConfidence(words) + (index == previous ? stayBonus : 0)
            if score > bestScore {
                best = index
                bestScore = score
            }
        }
        return best
    }

    /// Joins neighbouring windows in the same language into regions.
    static func regions(cuts: [Double], languages: [Int], duration: Double) -> [Region] {
        let bounds = [0] + cuts + [duration]
        var regions: [Region] = []
        for (index, language) in languages.enumerated() where index + 1 < bounds.count {
            if let last = regions.last, last.language == language {
                regions[regions.count - 1].end = bounds[index + 1]
            } else {
                regions.append(Region(start: bounds[index], end: bounds[index + 1], language: language))
            }
        }
        return regions
    }

    // MARK: Pieces

    /// The audio to transcribe for a piece from `start` to `end`: padded
    /// either side, within the dictation.
    static func padded(start: Double, end: Double, by padding: Double, duration: Double) -> ClosedRange<Double> {
        max(0, start - padding)...min(duration, end + padding)
    }

    /// The words of a padded piece's transcript that belong to the piece
    /// itself. `offset` is where the padded audio began; the first and last
    /// pieces keep everything before and after them.
    static func inside(_ words: [Word], offset: Double, start: Double, end: Double,
                       isFirst: Bool, isLast: Bool) -> [Word] {
        words.filter { word in
            let middle = offset + word.middle
            return (isFirst || middle >= start) && (isLast || middle < end)
        }
    }

    // MARK: Script

    /// Stretches of words with Latin letters in them, as index ranges.
    /// Stretches only punctuation apart, and close together, are one.
    static func latinSpans(_ words: [Word], join: Double = spanJoin) -> [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        for (index, word) in words.enumerated() where hasLatinLetter(word.text) {
            if let last = spans.last {
                let between = words[(last.upperBound + 1)..<index]
                let adjacent = last.upperBound == index - 1
                let close = word.start - words[last.upperBound].end < join && between.allSatisfy { !hasWordCharacter($0.text) }
                if adjacent || close {
                    spans[spans.count - 1] = last.lowerBound...index
                    continue
                }
            }
            spans.append(index...index)
        }
        return spans
    }

    /// Whether the other language's redo of a stretch should replace what
    /// the base model wrote there.
    static func shouldSplice(own: [Word], redo: [Word]) -> Bool {
        guard !redo.isEmpty else { return false }
        let redoConfidence = meanConfidence(redo)
        return redoConfidence >= spliceMinimum && redoConfidence > meanConfidence(own) - spliceMargin
    }

    // MARK: Text

    /// Pieces of text in order, as one string: each piece keeps the spacing
    /// its model gave it, Latin words never run into each other or into the
    /// punctuation before them, and runs of spaces become one.
    static func join(_ pieces: [String]) -> String {
        var text = ""
        for piece in pieces where !piece.isEmpty {
            if let last = text.last, let first = piece.first, !last.isWhitespace, isLatinLetterOrDigit(first),
               isLatinLetterOrDigit(last) || ".,!?;:)…".contains(last) {
                text += " "
            }
            text += piece
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A stretch redone in another language, to go back inside a sentence:
    /// without the full stop its model put at the end of the clip.
    static func spliced(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespaces)
        while let last = text.last, ".!?。".contains(last) { text.removeLast() }
        return " \(text) "
    }

    private static func hasLatinLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
    }

    private static func hasWordCharacter(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    private static func isLatinLetterOrDigit(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
