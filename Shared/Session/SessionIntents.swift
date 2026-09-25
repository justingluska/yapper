import ActivityKit
import AppIntents
import Foundation

/// The Live Activity that shows a dictation session on the Lock Screen and in
/// the Dynamic Island. Compiled into the app (which starts and updates it)
/// and the widget extension (which draws it).
struct SessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var sessionEnds: Date?
        var recordingStarted: Date?
        var lastWords: Int
    }
}

/// "Start dictating": for the Action Button, a Control Center control,
/// Shortcuts and Siri. Opens Yapper and starts recording.
struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictating"
    static let description = IntentDescription("Opens Yapper and starts listening. Your words are copied when you finish.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Bridge.requestStart(from: .shortcut)
        // If Yapper is already running it picks this up immediately;
        // otherwise it finds the request when it becomes active.
        NotificationCenter.default.post(name: .yapperStartRequested, object: nil)
        return .result()
    }
}

/// The End button on the Live Activity. Runs in the app's process.
struct EndSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Yapper Session"
    static let description = IntentDescription("Turns off the microphone and ends the dictation session.")

    func perform() async throws -> some IntentResult {
        Bridge.send(.endSession)
        return .result()
    }
}

extension Notification.Name {
    static let yapperStartRequested = Notification.Name("yapperStartRequested")
}
