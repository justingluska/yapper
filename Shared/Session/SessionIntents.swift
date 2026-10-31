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
        /// The recording started hands-free (`YapIntent`) and stops by itself.
        var handsFree: Bool? = nil
        /// The last hands-free dictation was copied; `lastWords` is its length.
        var copied: Bool? = nil
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

/// "Yap with Yapper": hands-free dictation, for Siri while driving, the
/// Action Button, Control Center and Shortcuts. Starts listening without
/// opening Yapper (or unlocking the iPhone), stops once you stop talking, and
/// saves the words to History and the clipboard. Run again while it's
/// listening, it finishes early.
struct YapIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Yap Hands-Free"
    static let description = IntentDescription("Starts listening without opening Yapper and stops when you stop talking. Your words are saved to History and copied.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let yap = EngineHook.yap else { throw EngineHook.Failure("Open Yapper once, then try again.") }
        try yap()
        return .result()
    }
}

/// The Done button on the Live Activity while Yapper is listening.
struct FinishDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Finish Dictating"
    static let description = IntentDescription("Stops listening and types out what you said.")

    func perform() async throws -> some IntentResult {
        Bridge.send(.stop)
        return .result()
    }
}

/// How the intents above reach the app's DictationController. They're
/// compiled into the widget extension too (for its controls), where these
/// stay nil and are never called.
enum EngineHook {
    @MainActor static var turnOn: (() throws -> Void)?
    @MainActor static var yap: (() throws -> Void)?

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
