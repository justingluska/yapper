import Foundation

/// What turned the audio into text.
enum Engine: String, Codable {
    /// Parakeet on the Neural Engine: the normal path.
    case parakeetNeuralEngine = "parakeet.ane"
    /// Parakeet on the CPU, after iOS refused the Neural Engine.
    case parakeetCPU = "parakeet.cpu"
    /// Apple's older on-device recognizer (SFSpeechRecognizer).
    case apple = "apple"
    /// Apple's SpeechAnalyzer model, iOS 26 and later.
    case appleAnalyzer = "apple.analyzer"

    var label: String {
        switch self {
        case .parakeetNeuralEngine: return "Parakeet · Neural Engine"
        case .parakeetCPU: return "Parakeet · CPU"
        case .apple: return "Apple on-device"
        case .appleAnalyzer: return "Apple on-device · SpeechAnalyzer"
        }
    }

    var explanation: String {
        switch self {
        case .parakeetNeuralEngine:
            return "NVIDIA's Parakeet model ran on your iPhone's Neural Engine, the chip built for this kind of work. This is the normal, fastest path."
        case .parakeetCPU:
            return "Parakeet ran on the CPU instead of the Neural Engine, because iOS didn't allow the Neural Engine at that moment. Same model and accuracy, just slower and a bit harder on the battery."
        case .apple:
            return "Apple's speech recognizer, forced to run on this iPhone with nothing sent to Apple. Yapper uses it when you choose it in Settings, or while no Parakeet model is ready (never when Only use Parakeet is on)."
        case .appleAnalyzer:
            return "Apple's newer on-device model (SpeechAnalyzer, iOS 26), the one behind transcription in Notes and Voice Memos. It runs on this iPhone and sends nothing to Apple. Yapper uses it when you choose Apple on-device, or while no Parakeet model is ready (never when Only use Parakeet is on)."
        }
    }
}

/// One finished dictation, kept on the device only.
struct DictationRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
    /// The model's output before cleanup, so a bad cleanup can be undone.
    var raw: String
    var duration: TimeInterval
    /// An `Engine` raw value (older records hold a display name instead).
    var engine: String
    /// Which Parakeet model, when Parakeet did the work.
    var model: String?
    /// Seconds spent transcribing.
    var processingTime: TimeInterval?
    /// Why a fallback engine was used, when one was.
    var note: String?
    /// Set when the dictation failed: what went wrong. `text` is empty.
    var error: String?
    /// The saved recording's file name, while Yapper keeps it (Settings ›
    /// Keep recordings). Nil once it's gone.
    var audioFile: String?
    /// How a dictation in two languages was split up, when a second
    /// language is on (Settings › Languages). Nil otherwise.
    var languages: LanguageBreakdown? = nil

    var failed: Bool { error != nil }
    var engineKind: Engine? { Engine(rawValue: engine) }
    var engineLabel: String { engineKind?.label ?? engine }
    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// How Yapper heard a dictation in two languages, for History: which
/// language each part was in, and how it decided.
struct LanguageBreakdown: Codable, Hashable {
    enum Method: String, Codable {
        /// Short windows, each given to the language whose model was surer.
        case windows
        /// The non-Latin language's model, with its Latin-letter stretches
        /// redone in the other language.
        case script
    }

    /// A stretch of the dictation in one language.
    struct Part: Codable, Hashable {
        /// A locale identifier, "es-US".
        var language: String
        /// Seconds into the recording.
        var start: Double
        var end: Double
        var text: String
        /// How sure that language's model was of these words, 0...1.
        var confidence: Double
    }

    /// The two languages listened for, this iPhone's first.
    var languages: [String]
    var method: Method
    var parts: [Part]
    /// How many times a model listened to some or all of the recording.
    var passes: Int
    /// The split was found but not used: the whole dictation in one
    /// language read as surer. The language it was kept in.
    var keptWhole: String?
    /// What each language's model heard in the whole dictation on its own,
    /// before any splitting, for History's details. Nil on older records.
    var heard: [Part]? = nil
}

/// One day's totals in Stats.
struct DayTotals: Codable, Equatable {
    var words = 0
    var dictations = 0
    var seconds: Double = 0

    /// Combines two sets of days by taking the larger of each total, so a
    /// merge can be repeated without counting anything twice.
    static func merged(_ a: [String: DayTotals], _ b: [String: DayTotals]) -> [String: DayTotals] {
        a.merging(b) { old, new in
            DayTotals(words: max(old.words, new.words),
                      dictations: max(old.dictations, new.dictations),
                      seconds: max(old.seconds, new.seconds))
        }
    }
}
