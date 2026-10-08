import Foundation

/// How long Yapper keeps recordings, in hours: 0 keeps none, -1 keeps them
/// forever.
enum Retention {
    static let recordingChoices = [0, 1, 24, 7 * 24, 30 * 24, 90 * 24, -1]
    static let defaultRecordingHours = 30 * 24

    /// Whether something from `date` is past a limit of `hours` at `now`.
    static func isExpired(_ date: Date, hours: Int, now: Date = Date()) -> Bool {
        if hours < 0 { return false }
        if hours == 0 { return true }
        return date < now.addingTimeInterval(-Double(hours) * 3_600)
    }

    /// "Don't keep", "1 hour", "7 days", "Forever".
    static func label(hours: Int) -> String {
        switch hours {
        case ..<0: return "Forever"
        case 0: return "Don't keep"
        case 1: return "1 hour"
        case let h where h % 24 == 0: return h == 24 ? "1 day" : "\(h / 24) days"
        default: return "\(hours) hours"
        }
    }

    /// For a sentence: "for 7 days", "forever", "not at all".
    static func phrase(hours: Int) -> String {
        switch hours {
        case ..<0: return "forever"
        case 0: return "not at all"
        default: return "for \(label(hours: hours))"
        }
    }
}
