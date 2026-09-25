import SwiftUI
import UIKit

/// Keyboard state. The keyboard is a remote control for the Yapper app,
/// which does the actual listening, plus the few keys you need around it.
@MainActor
final class KeyboardModel: ObservableObject {
    /// Voice: the mic. Typing: QWERTY. Without Full Access only typing works,
    /// so the keyboard opens in typing mode.
    enum Mode { case voice, typing }
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, on, locked }

    @Published var compact = false
    @Published var mode: Mode = .voice
    @Published var layer: Layer = .letters
    @Published var shift: Shift = .on
    @Published private(set) var phase: Bridge.Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var recordingStarted: Date?
    @Published private(set) var sessionEnds: Date?
    @Published private(set) var hasFullAccess = false
    @Published var banner: String?
    /// Shown for a few seconds after an insert.
    @Published private(set) var undoText: String?
    /// True between a mic tap and the app answering, for the warm path.
    @Published private(set) var waitingForApp = false

    private weak var controller: KeyboardViewController?
    private let signals = SignalObserver()
    private var poll: Timer?
    private var undoTimer: Timer?
    private var startTimeout: DispatchWorkItem?
    private var insertRetries = 0

    init(controller: KeyboardViewController) {
        self.controller = controller
        signals.observe(.stateChanged) { [weak self] in self?.refresh() }
        signals.observe(.resultReady) { [weak self] in
            self?.insertRetries = 2
            self?.insertPendingResult()
        }
    }

    /// A model frozen in one state, for screenshots of the layout outside a
    /// real keyboard (the KeyboardPreview target). It has no controller, so
    /// its keys do nothing.
    init(preview phase: Bridge.Phase, sessionEnds: Date? = nil, undo: String? = nil, banner: String? = nil,
         waitingForApp: Bool = false, compact: Bool = false, mode: Mode = .voice) {
        self.mode = mode
        self.phase = phase
        self.sessionEnds = sessionEnds
        self.hasFullAccess = true
        self.recordingStarted = phase == .recording ? Date().addingTimeInterval(-7) : nil
        self.undoText = undo
        self.banner = banner
        self.waitingForApp = waitingForApp
        self.compact = compact
    }

    /// Feeds the level bars in a preview.
    func previewLevel(_ value: Float) {
        level = value
    }

    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    var needsGlobe: Bool { controller?.needsInputModeSwitchKey ?? true }

    var returnLabel: String {
        switch proxy?.returnKeyType ?? .default {
        case .go: return "go"
        case .google, .search, .yahoo: return "search"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .send: return "send"
        case .done: return "done"
        case .emergencyCall: return "call"
        case .continue: return "continue"
        default: return "return"
        }
    }

    var returnIsPrimary: Bool {
        guard let type = proxy?.returnKeyType else { return false }
        return type != .default
    }

    // MARK: Lifecycle

    func appear() {
        hasFullAccess = controller?.hasFullAccess ?? false
        Bridge.defaults.set(true, forKey: Bridge.Key.keyboardSeen)
        if hasFullAccess {
            Bridge.defaults.set(true, forKey: Bridge.Key.fullAccessSeen)
        } else {
            mode = .typing
        }
        updateAutoShift()
        banner = nil
        // Errors from before this keyboard appeared aren't news.
        errorShownFor = Bridge.lastError
        refresh()
        startPolling()
        // Back from a cold start: the text is waiting.
        insertRetries = 1
        insertPendingResult()
    }

    func disappear() {
        poll?.invalidate()
        poll = nil
    }

    func textDidChange() {
        updateAutoShift()
    }

    private func startPolling() {
        poll?.invalidate()
        // Level for the waveform and the heartbeat watchdog. Cheap: a few
        // UserDefaults reads, ten times a second, only while visible.
        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    private func refresh() {
        guard hasFullAccess else { return }
        let live = Bridge.livePhase
        if live != phase { phase = live }
        let ends = live == .idle ? nil : Bridge.sessionEnds
        if ends != sessionEnds { sessionEnds = ends }
        if live == .recording {
            level = Bridge.level
            recordingStarted = Bridge.recordingStarted
        } else {
            level = 0
            recordingStarted = nil
        }
        if waitingForApp, live == .recording {
            waitingForApp = false
            startTimeout?.cancel()
        }
        // Show an error the app reported after this keyboard's last mic tap.
        if let error = Bridge.lastError, !error.isEmpty, error != errorShownFor {
            errorShownFor = error
            banner = error
        }
    }

    private var errorShownFor: String?

    // MARK: Dictation

    func micTapped() {
        mode = .voice
        guard hasFullAccess else {
            banner = "Turn on Allow Full Access for Yapper in Settings › General › Keyboard › Keyboards to dictate."
            return
        }
        banner = nil
        errorShownFor = Bridge.lastError
        switch Bridge.livePhase {
        case .recording:
            Bridge.send(.stop)
        case .transcribing, .preparing:
            break
        case .ready:
            // Warm path: the app is alive with the mic on. Ask it to record,
            // and fall back to opening it if it doesn't answer.
            waitingForApp = true
            Bridge.send(.start)
            let fallback = DispatchWorkItem { [weak self] in
                guard let self, self.waitingForApp else { return }
                self.waitingForApp = false
                self.openAppToDictate()
            }
            startTimeout = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)
        case .idle:
            openAppToDictate()
        }
        Feedback.tap()
    }

    func cancelTapped() {
        Bridge.send(.cancel)
        Feedback.tap()
    }

    func endSessionTapped() {
        Bridge.send(.endSession)
        Feedback.tap()
    }

    func setSwiftUIOpen(_ open: @escaping (URL) -> Void) {
        controller?.swiftUIOpen = open
    }

    private func openAppToDictate() {
        Bridge.requestStart(from: .keyboard)
        controller?.openApp(Bridge.dictateURL)
    }

    private func insertPendingResult() {
        guard let result = Bridge.unconsumedResult else {
            // Cross-process UserDefaults can lag the Darwin notification.
            if insertRetries > 0 {
                insertRetries -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.insertPendingResult() }
            }
            return
        }
        // Claim before inserting, so a duplicate notification can't insert twice.
        Bridge.markConsumed(result)
        guard let proxy else { return }
        let fitted = TextProcessor.fit(
            result.text,
            before: proxy.documentContextBeforeInput,
            after: proxy.documentContextAfterInput,
            autocapitalize: proxy.autocapitalizationType != UITextAutocapitalizationType.none
        )
        proxy.insertText(fitted)
        showUndo(fitted)
        Feedback.success()
    }

    private func showUndo(_ text: String) {
        undoText = text
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.undoText = nil }
        }
    }

    func undoTapped() {
        guard let text = undoText, let proxy else { return }
        if (proxy.documentContextBeforeInput ?? "").hasSuffix(text) {
            for _ in text { proxy.deleteBackward() }
        }
        undoText = nil
        Feedback.tap()
    }

    // MARK: Keys

    func deleteBackward() {
        proxy?.deleteBackward()
        Feedback.key()
    }

    /// Deletes back to the previous word boundary (used once delete-repeat
    /// has been held for a while).
    func deleteWord() {
        guard let proxy, let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            proxy?.deleteBackward()
            return
        }
        var count = 0
        var sawWord = false
        for char in before.reversed() {
            if char.isWhitespace || char.isPunctuation {
                if sawWord { break }
            } else {
                sawWord = true
            }
            count += 1
        }
        for _ in 0..<max(count, 1) { proxy.deleteBackward() }
    }

    func space() {
        guard let proxy else { return }
        // Double space types ". " in typing mode, like the system keyboard.
        if mode == .typing, let last = lastSpaceTap, Date().timeIntervalSince(last) < 0.4,
           let before = proxy.documentContextBeforeInput, before.hasSuffix(" "),
           let prior = before.dropLast().last, prior.isLetter || prior.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastSpaceTap = nil
        } else {
            proxy.insertText(" ")
            lastSpaceTap = Date()
        }
        if layer != .letters { layer = .letters }
        Feedback.key()
    }

    private var lastSpaceTap: Date?

    // MARK: Typing

    func showTyping() {
        mode = .typing
        updateAutoShift()
        Feedback.tap()
    }

    func type(_ key: String) {
        guard let proxy else { return }
        let text = layer == .letters && shift != .off ? key.uppercased() : key
        proxy.insertText(text)
        if shift == .on { shift = .off }
        undoText = nil
        Feedback.key()
    }

    func shiftTapped() {
        switch shift {
        case .off: shift = .on
        case .on, .locked: shift = .off
        }
        Feedback.key()
    }

    func shiftDoubleTapped() {
        shift = .locked
    }

    func switchLayer(_ layer: Layer) {
        self.layer = layer
        Feedback.key()
    }

    private func updateAutoShift() {
        guard shift != .locked, layer == .letters, let proxy else { return }
        switch proxy.autocapitalizationType ?? .sentences {
        case .none:
            shift = .off
        case .allCharacters:
            shift = .on
        case .words:
            let before = proxy.documentContextBeforeInput ?? ""
            shift = before.isEmpty || before.last?.isWhitespace == true ? .on : .off
        default:
            let before = proxy.documentContextBeforeInput ?? ""
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            let atStart = trimmed.isEmpty || before.hasSuffix("\n")
            let afterSentence = before.hasSuffix(" ") && (trimmed.last.map { ".!?".contains($0) } ?? false)
            shift = atStart || afterSentence ? .on : .off
        }
    }

    func returnKey() {
        proxy?.insertText("\n")
        Feedback.key()
    }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }
}

enum Feedback {
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static func key() {
        UIDevice.current.playInputClick()
        guard Settings.haptics else { return }
        light.impactOccurred(intensity: 0.5)
    }

    static func tap() {
        guard Settings.haptics else { return }
        light.impactOccurred()
    }

    static func success() {
        guard Settings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
