import Foundation

/// How the keyboard and the app talk to each other.
///
/// iOS keyboards cannot use the microphone, so the app does the recording and
/// transcribing while it sits in the background, and the keyboard is a remote
/// control. They share two channels:
///
/// - **State** lives in the App Group's UserDefaults: whether a session is
///   live, what it is doing, the audio level for the waveform, and the latest
///   transcript waiting to be inserted.
/// - **Signals** are Darwin notifications, which cross process boundaries but
///   carry no payload. The sender writes state first, then posts; the receiver
///   reads state when it hears the signal.
///
/// Darwin notifications do not wake a suspended app. That is fine: the app is
/// only reachable while a session keeps its audio engine (and therefore the
/// process) running, and the keyboard checks the heartbeat to know that.
enum Bridge {
    static let appGroup = "group.com.gluska.yapper"
    static let urlScheme = "yapper"

    /// Read ten times a second by the keyboard and on every audio buffer by
    /// the app, so it's created once.
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// `yapper://dictate`: opened by the keyboard to start a session.
    static let dictateURL = URL(string: "\(urlScheme)://dictate")!

    // MARK: Signals

    enum Signal: String, CaseIterable {
        /// Keyboard → app
        case start = "com.gluska.yapper.start"
        case stop = "com.gluska.yapper.stop"
        case cancel = "com.gluska.yapper.cancel"
        case endSession = "com.gluska.yapper.end-session"
        /// App → keyboard
        case stateChanged = "com.gluska.yapper.state"
        case resultReady = "com.gluska.yapper.result"
    }

    /// Sends a keyboard → app command. Darwin notifications can be posted
    /// by any app on the phone, so each command also writes a one-time token
    /// to the App Group, which only Yapper's own targets can write. The app
    /// acts on a command only with a fresh, unused token (`accept`).
    static func send(_ signal: Signal) {
        let token = "\(signal.rawValue)|\(UUID().uuidString)|\(Date().timeIntervalSince1970)"
        defaults.set(token, forKey: Key.command)
        post(signal)
    }

    /// Calls `action` if the App Group holds a fresh, unused token for
    /// `signal`. Cross-process defaults can lag the notification by a moment,
    /// so it looks a few times before giving up. Main queue only.
    static func accept(_ signal: Signal, _ action: @escaping @MainActor () -> Void) {
        func attempt(_ remaining: Int) {
            if let raw = defaults.string(forKey: Key.command) {
                let parts = raw.split(separator: "|").map(String.init)
                if parts.count == 3, parts[0] == signal.rawValue, parts[1] != lastAcceptedToken,
                   let sent = Double(parts[2]), Date().timeIntervalSince1970 - sent < 3 {
                    lastAcceptedToken = parts[1]
                    MainActor.assumeIsolated { action() }
                    return
                }
            }
            guard remaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { attempt(remaining - 1) }
        }
        attempt(4)
    }

    private static var lastAcceptedToken: String?

    static func post(_ signal: Signal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.rawValue as CFString),
            nil, nil, true
        )
    }

    // MARK: Shared state

    enum Phase: String, Codable {
        /// No session: the app may not even be running.
        case idle
        /// Session live, microphone warm, waiting for the mic key.
        case ready
        case recording
        case transcribing
        /// The model is still downloading or loading.
        case preparing
    }

    enum Key {
        static let phase = "bridge.phase"
        static let heartbeat = "bridge.heartbeat"
        static let sessionEnds = "bridge.sessionEnds"
        static let level = "bridge.level"
        static let recordingStarted = "bridge.recordingStarted"
        static let resultID = "bridge.resultID"
        static let resultText = "bridge.resultText"
        static let resultConsumedID = "bridge.resultConsumedID"
        static let resultDate = "bridge.resultDate"
        static let lastError = "bridge.lastError"
        static let pendingStart = "bridge.pendingStart"
        static let keyboardSeen = "bridge.keyboardSeen"
        static let fullAccessSeen = "bridge.fullAccessSeen"
        static let command = "bridge.command"
    }

    /// The app writes a heartbeat every second while a session is live. A
    /// stale heartbeat means the app was killed or suspended and the keyboard
    /// has to open it again.
    static let heartbeatTimeout: TimeInterval = 3.5

    static var phase: Phase {
        get { Phase(rawValue: defaults.string(forKey: Key.phase) ?? "") ?? .idle }
        set { defaults.set(newValue.rawValue, forKey: Key.phase) }
    }

    static var isAppAlive: Bool {
        let beat = defaults.double(forKey: Key.heartbeat)
        return beat > 0 && Date().timeIntervalSince1970 - beat < heartbeatTimeout
    }

    /// Phase as the keyboard should see it: anything but idle is only real
    /// while the heartbeat is fresh.
    static var livePhase: Phase {
        let phase = self.phase
        return phase != .idle && isAppAlive ? phase : .idle
    }

    static var level: Float {
        get { defaults.float(forKey: Key.level) }
        set { defaults.set(newValue, forKey: Key.level) }
    }

    static var recordingStarted: Date? {
        get {
            let t = defaults.double(forKey: Key.recordingStarted)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.recordingStarted) }
    }

    static var sessionEnds: Date? {
        get {
            let t = defaults.double(forKey: Key.sessionEnds)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.sessionEnds) }
    }

    static var lastError: String? {
        get { defaults.string(forKey: Key.lastError) }
        set { defaults.set(newValue, forKey: Key.lastError) }
    }

    /// Who asked the app to start recording as soon as it opens.
    enum StartSource: String {
        /// The keyboard: the transcript goes back to the keyboard.
        case keyboard
        /// Action Button, Control Center, Siri, Shortcuts: copied to the clipboard.
        case shortcut
    }

    /// Written just before the app is opened, so it starts recording straight
    /// away instead of showing its home screen. Expires after 30 seconds so a
    /// stale request never turns the mic on later.
    static func requestStart(from source: StartSource) {
        defaults.set(source.rawValue, forKey: Key.pendingStart)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.pendingStart + ".at")
    }

    /// Returns and clears the pending request, if it is fresh.
    static func takeStartRequest() -> StartSource? {
        let raw = defaults.string(forKey: Key.pendingStart)
        let at = defaults.double(forKey: Key.pendingStart + ".at")
        defaults.removeObject(forKey: Key.pendingStart)
        guard let raw, Date().timeIntervalSince1970 - at < 30 else { return nil }
        return StartSource(rawValue: raw)
    }

    // MARK: Results

    struct Result: Equatable {
        let id: String
        let text: String
    }

    /// Publishes a finished transcript for the keyboard to insert.
    static func publish(_ text: String) {
        let id = UUID().uuidString
        defaults.set(text, forKey: Key.resultText)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.resultDate)
        defaults.set(id, forKey: Key.resultID)
        post(.resultReady)
    }

    /// A result older than this is not inserted when the keyboard next
    /// appears: by then the user is probably typing somewhere else. It is
    /// still in History.
    static let resultLifetime: TimeInterval = 120

    /// The transcript the keyboard has not inserted yet, if any.
    static var unconsumedResult: Result? {
        guard let id = defaults.string(forKey: Key.resultID),
              id != defaults.string(forKey: Key.resultConsumedID),
              let text = defaults.string(forKey: Key.resultText),
              Date().timeIntervalSince1970 - defaults.double(forKey: Key.resultDate) < resultLifetime
        else { return nil }
        return Result(id: id, text: text)
    }

    static func markConsumed(_ result: Result) {
        defaults.set(result.id, forKey: Key.resultConsumedID)
    }
}

/// Listens for Darwin notifications and calls back on the main queue.
final class SignalObserver {
    private var handlers: [String: @MainActor () -> Void] = [:]

    init() {}

    func observe(_ signal: Bridge.Signal, _ handler: @escaping @MainActor () -> Void) {
        handlers[signal.rawValue] = handler
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let me = Unmanaged<SignalObserver>.fromOpaque(observer).takeUnretainedValue()
                let key = name.rawValue as String
                DispatchQueue.main.async { MainActor.assumeIsolated { me.handlers[key]?() } }
            },
            signal.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
