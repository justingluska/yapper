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

/// "Turn On Yapper": starts the speech engine without opening Yapper, from
/// the Action Button, Control Center, the Lock Screen, Siri or Shortcuts.
/// Afterwards the keyboard dictates in any app with no trip to Yapper.
/// iOS lets an app start the microphone in the background only through an
/// audio-recording intent, and only with a Live Activity showing it.
struct TurnOnEngineIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn On Yapper"
    static let description = IntentDescription("Turns on Yapper's speech engine without leaving the app you're in, so the Yapper keyboard dictates right away.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        // Runs in the app's process, where Yapper sets this at launch.
        guard let turnOn = EngineHook.turnOn else { throw EngineHook.Failure("Open Yapper once, then try again.") }
        try turnOn()
        return .result()
    }
}

/// How the intent above reaches the app's DictationController. The intent is
/// compiled into the widget extension too (for its control), where this
/// stays nil and is never called.
enum EngineHook {
    @MainActor static var turnOn: (() throws -> Void)?

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
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
