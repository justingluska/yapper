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
        var replacements: [Replacement] = []
    }

    /// Filler words dropped when they stand alone. "like", "you know", "ah"
    /// and "mhm" stay: they carry meaning too often to remove blindly.
    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm"]

    static func clean(_ raw: String, options: Options = Options()) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if options.removeFillers { text = removeFillers(text) }
        // Dictionary before stutters, so a phrase like "c plus plus" survives.
        text = applyReplacements(text, options.replacements)
        if options.removeRepeats { text = removeRepeats(text) }
        text = tidySpacing(text)
        return text
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
