import Foundation

/// A personal-dictionary entry: "when I say X, write Y".
struct Replacement: Codable, Hashable, Identifiable {
    var id = UUID()
    var spoken: String
    var written: String
}

/// Rule-based cleanup that runs on every transcript. It is deliberately
/// conservative: it removes what nobody means to type (fillers, stutters) and
/// never rewrites wording.
enum TextProcessor {
    struct Options: Equatable {
        var removeFillers = true
        var removeRepeats = true
        /// Off: no commas, full stops or question marks, just the words.
        var punctuation = true
        /// On: every letter the model wrote is lowercase (dictionary words
        /// keep the spelling you gave them).
        var lowercase = false
        /// "comma", "period", "question mark", "new line"… said out loud
        /// become the mark, even with punctuation off.
        var spokenPunctuation = true
        var replacements: [Replacement] = []
    }

    /// Filler words dropped when they stand alone. "like", "you know", "ah"
    /// and "mhm" stay: they carry meaning too often to remove blindly.
    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm"]

    static func clean(_ raw: String, options: Options = Options()) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if options.removeFillers { text = removeFillers(text) }
        // Said marks become placeholders the punctuation pass can't see, so
        // they survive it; they turn into real marks at the end.
        if options.spokenPunctuation { text = markSpokenPunctuation(text) }
        // After fillers (they lean on the commas) and before the dictionary,
        // so a written "Dr." or "C++" keeps its marks.
        if !options.punctuation { text = removePunctuation(text) }
        if options.lowercase { text = text.lowercased() }
        // Dictionary before stutters, so a phrase like "c plus plus" survives.
        text = applyReplacements(text, options.replacements)
        if options.removeRepeats { text = removeRepeats(text) }
        if options.spokenPunctuation { text = resolveSpokenPunctuation(text, capitalize: !options.lowercase) }
        text = tidySpacing(text)
        return text
    }

    // MARK: Spoken punctuation

    /// What can be said, longest first so "semicolon" wins over "colon".
    /// Placeholders are private-use characters no model writes.
    static let spokenMarks: [(words: String, placeholder: Character, mark: String)] = [
        ("new paragraph", "\u{E001}", "\n\n"),
        ("new line", "\u{E002}", "\n"),
        ("exclamation point", "\u{E003}", "!"),
        ("exclamation mark", "\u{E003}", "!"),
        ("question mark", "\u{E004}", "?"),
        ("semi colon", "\u{E005}", ";"),
        ("semicolon", "\u{E005}", ";"),
        ("full stop", "\u{E006}", "."),
        ("period", "\u{E006}", "."),
        ("comma", "\u{E007}", ","),
        ("colon", "\u{E008}", ":"),
    ]

    /// After one of these, the word is the thing, not the mark: "a period of
    /// time", "the Oxford comma", "my colon".
    private static let keepsTheWord: Set<String> = [
        "a", "an", "the", "this", "that", "each", "every", "any", "one", "my", "your", "his", "her", "their",
        "our", "its", "trial", "grace", "waiting", "time", "oxford", "serial", "same", "first", "last", "next",
    ]

    /// Domain endings that make "dot" a dot: "gold dot com" → "gold.com".
    private static let domainEndings = "com|org|net|io|co|ai|app|dev|edu|gov|me|us|uk|ca|tv|xyz"
    private static let dotPlaceholder: Character = "\u{E009}"

    /// Swaps each said mark for its placeholder, along with any punctuation
    /// the model put around the word ("Hello, comma, how" → "Hello⟨,⟩ how").
    static func markSpokenPunctuation(_ text: String) -> String {
        var result = text
        // "gold dot com", and a "dot" that ends the dictation.
        result = result.replacingOccurrences(
            of: "(?i)(?<=\\p{L}|\\p{N})\\s+dot\\s+(?=(?:\(domainEndings))\\b)", with: String(dotPlaceholder),
            options: .regularExpression)
        result = result.replacingOccurrences(
            of: "(?i)\\s+dot[.!?,]*\\s*$", with: String(spokenMarks.first { $0.mark == "." }!.placeholder),
            options: .regularExpression)

        for entry in spokenMarks {
            let words = entry.words.replacingOccurrences(of: " ", with: "\\s+")
            guard let regex = try? NSRegularExpression(pattern: "(?i)[,.;:!?]*\\s*\\b\(words)\\b[,.;:!?]*") else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let previous = result[..<range.lowerBound].split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).last
                if let previous, keepsTheWord.contains(previous.lowercased()) { continue }
                // Nothing said before it: a lone "comma" is just the word.
                if previous == nil { continue }
                result.replaceSubrange(range, with: String(entry.placeholder))
            }
        }
        return result
    }

    /// Turns placeholders into marks: tight to the word before, one space
    /// after, and a capital after a said full stop, question or exclamation.
    static func resolveSpokenPunctuation(_ text: String, capitalize: Bool) -> String {
        var marks: [Character: String] = [dotPlaceholder: "."]
        for entry in spokenMarks { marks[entry.placeholder] = entry.mark }
        guard text.contains(where: { marks[$0] != nil }) else { return text }

        var output = ""
        var capitalizeNext = false
        var pendingSpace = false
        for char in text {
            if char == dotPlaceholder {
                while output.last == " " { output.removeLast() }
                output += "."
                pendingSpace = false
                continue
            }
            if let mark = marks[char] {
                while output.last == " " { output.removeLast() }
                output += mark
                if mark.hasSuffix("\n") {
                    pendingSpace = false
                    capitalizeNext = capitalize
                } else {
                    pendingSpace = true
                    capitalizeNext = capitalize && ".!?".contains(mark)
                }
                continue
            }
            if char == " " {
                if output.last?.isNewline == true { continue }
                if pendingSpace { continue }
            }
            if pendingSpace, !",.;:!?".contains(char) {
                output += " "
            }
            pendingSpace = false
            if capitalizeNext, char.isLetter {
                output += char.uppercased()
                capitalizeNext = false
            } else {
                if !char.isWhitespace { capitalizeNext = false }
                output.append(char)
            }
        }
        return output
    }

    /// Removes standalone fillers along with the comma that usually follows
    /// them, keeping sentence capitalization and commas balanced:
    /// "Um, so I think" → "So I think", "I was, um, thinking" → "I was thinking".
    static func removeFillers(_ text: String) -> String {
        let alternatives = fillers.sorted { $0.count > $1.count }.joined(separator: "|")
        // A filler plus any trailing commas/ellipsis and spaces.
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\b(?:\(alternatives))\\b[,…]*\\s*") else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = text.startIndex
        var capitalizeNext = false
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            var segment = String(text[cursor..<range.lowerBound])
            if capitalizeNext, !segment.isEmpty {
                segment = capitalizeFirst(segment)
                capitalizeNext = false
            }
            output += segment
            // "was, um, thinking": the filler sat between two commas; drop
            // the first so the clause reads straight through.
            if text[range].contains(","), output.hasSuffix(", ") {
                output.removeLast(2)
                output += " "
            }
            if isSentenceStart(output) { capitalizeNext = true }
            cursor = range.upperBound
        }
        var tail = String(text[cursor...])
        if capitalizeNext { tail = capitalizeFirst(tail) }
        output += tail
        return output
    }

    /// Drops the punctuation a model adds between words: "Hey, are you
    /// free? I'm out." → "Hey are you free I'm out". Marks inside a token
    /// stay, so "3.5", "1,000", "10:30", "gold.com" and "don't" survive;
    /// so do quotes, dashes and symbols like $ % @ #.
    static func removePunctuation(_ text: String) -> String {
        // Full-width marks (Chinese, Japanese) and Spanish openers always go.
        var result = text.replacingOccurrences(of: "[。、，！？；：¿¡]", with: " ", options: .regularExpression)
        // Elsewhere, a mark goes unless it sits between two letters or digits.
        result = result.replacingOccurrences(
            of: "(?<![\\p{L}\\p{N}])[.,!?;:…]+|[.,!?;:…]+(?![\\p{L}\\p{N}])",
            with: "", options: .regularExpression
        )
        return result.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// "I I think" → "I think", "the the" → "the". Only exact immediate repeats
    /// of the same word (case-insensitive), so "had had" is the one casualty
    /// we accept. Letters only: "555 555 1234" is a phone number, not a stutter.
    static func removeRepeats(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\b(\\p{L}+)(?:,?\\s+\\1\\b)+") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    static func applyReplacements(_ text: String, _ replacements: [Replacement]) -> String {
        var result = text
        // Longest phrases first, so "open ai dev day" wins over "open ai".
        for entry in replacements.sorted(by: { $0.spoken.count > $1.spoken.count }) {
            let spoken = entry.spoken.trimmingCharacters(in: .whitespaces)
            guard !spoken.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: spoken)
                .replacingOccurrences(of: " ", with: "\\s+")
            guard let regex = try? NSRegularExpression(pattern: "(?i)(?<![\\w])\(escaped)(?![\\w])") else { continue }
            let template = NSRegularExpression.escapedTemplate(for: entry.written)
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result
    }

    /// Collapses doubled spaces and removes spaces before punctuation left
    /// behind by the passes above.
    static func tidySpacing(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: ",{2,}", with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: "^[,.;:]\\s*", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// The Settings preview line: how a dictation reads with these choices.
    static func styleSample(punctuation: Bool, lowercase: Bool) -> String {
        clean("Hey, are you free Friday? I'll bring the snacks.",
              options: Options(removeFillers: false, removeRepeats: false, punctuation: punctuation, lowercase: lowercase))
    }

    // MARK: Fitting text into the field

    /// Adjusts a transcript for where it lands: a leading space when the
    /// cursor follows a word, lowercase first letter mid-sentence, capital
    /// after a sentence end or at the start of the field.
    static func fit(_ text: String, before: String?, after: String? = nil, autocapitalize: Bool = true) -> String {
        var result = text
        guard !result.isEmpty else { return text }
        let before = before ?? ""

        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        let lastChar = trimmedBefore.last
        let atFieldStart = trimmedBefore.isEmpty || before.hasSuffix("\n")
        let afterSentenceEnd = lastChar.map { ".!?".contains($0) } ?? true

        if autocapitalize {
            if atFieldStart || afterSentenceEnd {
                result = capitalizeFirst(result)
            } else if startsWithOrdinaryCapital(result) {
                result = lowercaseFirst(result)
            }
        }

        // Mid-sentence insert: drop a trailing period the model added, since
        // the user is continuing their own sentence.
        if !atFieldStart && !afterSentenceEnd, let after, !after.trimmingCharacters(in: .whitespaces).isEmpty,
           result.hasSuffix(".") {
            result.removeLast()
        }

        if let last = before.last, !last.isWhitespace, !"([{\"'“‘/@#".contains(last) {
            result = " " + result
        }
        if let first = after?.first, !first.isWhitespace, !".,!?;:)]}\"'”’".contains(first) {
            result += " "
        }
        return result
    }

    // MARK: Helpers

    private static func isSentenceStart(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        return ".!?\n".contains(last)
    }

    static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func lowercaseFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// True when the first word is capitalized only because it opens the
    /// transcript: "The", not "I", "I'm", "NASA" or "Justin" (a capital
    /// followed by lowercase is ambiguous; we only lowercase common words).
    private static func startsWithOrdinaryCapital(_ text: String) -> Bool {
        let firstWord = text.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        guard let first = firstWord.first, first.isUppercase else { return false }
        if firstWord == "I" || firstWord.hasPrefix("I'") || firstWord.hasPrefix("I’") { return false }
        if firstWord.count > 1 && firstWord.dropFirst().allSatisfy({ $0.isUppercase }) { return false }
        return commonWords.contains(firstWord.lowercased())
    }

    private static let commonWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "so", "then", "also", "because", "if", "when", "while",
        "it", "its", "it's", "this", "that", "these", "those", "there", "here", "we", "you", "they",
        "he", "she", "my", "our", "your", "their", "is", "are", "was", "were", "be", "to", "for",
        "of", "in", "on", "at", "with", "just", "maybe", "probably", "actually", "yeah", "yes", "no",
        "not", "can", "could", "would", "should", "will", "let's", "what", "why", "how", "which",
        "who", "where", "some", "all", "any", "more", "most", "very", "really", "please", "thanks",
        "okay", "ok", "well", "now", "still", "even", "as", "like", "about", "from", "by", "into",
    ]
}
