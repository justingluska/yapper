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

    var failed: Bool { error != nil }
    var engineKind: Engine? { Engine(rawValue: engine) }
    var engineLabel: String { engineKind?.label ?? engine }
    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
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
