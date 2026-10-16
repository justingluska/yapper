import AppKit
import AVFoundation
import Speech

/// The Mac app's engine room: hears the dictation key, records, transcribes
/// on this Mac and types the text into the app you're in.
@MainActor
final class MacDictation: ObservableObject {
    static let shared = MacDictation()

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double, label: String)
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelState: ModelState = .notDownloaded
    @Published private(set) var downloadedModels: Set<ModelChoice> = []
    /// The model being downloaded, if any.
    @Published private(set) var downloading: ModelChoice?
    @Published private(set) var appleState: AppleAnalyzer.State = .unsupported
    @Published private(set) var appleInstallProgress: Double?
    @Published private(set) var lastText: String?
    @Published private(set) var micPermission: AVAudioApplication.recordPermission = .undetermined
    @Published private(set) var speechAuthorized = false
    @Published private(set) var isTrusted = false
    /// Bumped whenever History changes, so open lists reload.
    @Published private(set) var historyVersion = 0

    /// Opens the main window; the menu bar scene hands it over at launch,
    /// since only SwiftUI views can open windows.
    var openMainWindow: (() -> Void)?

    private let transcriber = Transcriber()
    private let recorder = MacRecorder()
    private let hotkeys = HotkeyMonitor()
    private var gesture = TalkGesture()
    private var loadTask: Task<Void, Never>?
    private var trustTimer: Timer?
    private var launched = false

    private var hud: HUDController { .shared }

    /// Everything that must be in place to dictate.
    var isSetUp: Bool { micPermission == .granted && isTrusted }

    // MARK: Launch

    func launch() {
        guard !launched else { return }
        launched = true
        Transcriber.configure()
        refreshPermissions()
        refreshModels()

        recorder.onLevel = { level in
            DispatchQueue.main.async { HUDController.shared.push(level: level) }
        }
        recorder.onLost = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.phase == .recording else { return }
                self.gesture.reset()
                self.finishRecording()
            }
        }

        hotkeys.onPress = { [weak self] in self?.perform(self?.gesture.press(at: Self.now) ?? .none) }
        hotkeys.onRelease = { [weak self] in
            guard let self else { return }
            perform(gesture.release(at: Self.now))
            if gesture.state == .handsFree, phase == .recording { hud.showListening(handsFree: true) }
        }
        hotkeys.onOtherKey = { [weak self] in self?.perform(self?.gesture.otherKey(at: Self.now) ?? .none) }
        hotkeys.onEscape = { [weak self] in
            guard let self, phase == .recording else { return }
            cancelRecording()
        }
        hotkeys.start()
        watchTrust()

        RecordingStore.prune()
        Task { await loadModel() }
        Task { await refreshApple() }

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func perform(_ action: TalkGesture.Action) {
        switch action {
        case .none: break
        case .start: if !startRecording() { gesture.reset() }
        case .finish: finishRecording()
        case .cancel: cancelRecording()
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        micPermission = MacRecorder.permission
        speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        let trusted = TextInserter.isTrusted
        if trusted, !isTrusted { hotkeys.start() }
        isTrusted = trusted
        if isSetUp { Settings.onboarded = true }
    }

    func requestMicrophone() async {
        if MacRecorder.permission == .denied {
            open(Self.privacyURL("Privacy_Microphone"))
        } else {
            _ = await MacRecorder.requestPermission()
        }
        refreshPermissions()
    }

    func requestAccessibility() {
        TextInserter.requestTrust()
        open(Self.privacyURL("Privacy_Accessibility"))
        watchTrust()
    }

    func requestSpeech() async {
        if SFSpeechRecognizer.authorizationStatus() == .denied {
            open(Self.privacyURL("Privacy_SpeechRecognition"))
        } else {
            _ = await AppleSpeech.requestPermission()
        }
        refreshPermissions()
    }

    func openKeyboardSettings() {
        open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    private static func privacyURL(_ anchor: String) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// macOS says nothing when the user flips Accessibility on, so look
    /// once a second until it's on; the key monitors only hear other apps
    /// after that.
    private func watchTrust() {
        guard !TextInserter.isTrusted, trustTimer == nil else {
            refreshPermissions()
            return
        }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, TextInserter.isTrusted else { return }
                timer.invalidate()
                self.trustTimer = nil
                self.refreshPermissions()
            }
        }
    }

    // MARK: Dictation

    /// Returns false when it couldn't start, and says why.
    @discardableResult
    func startRecording() -> Bool {
        guard phase == .idle else {
            if phase == .transcribing { hud.showMessage("Still transcribing the last one") }
            return false
        }
        switch MacRecorder.permission {
        case .granted:
            break
        case .undetermined:
            Task { await requestMicrophone() }
            return false
        default:
            hud.showMessage("Yapper needs the microphone. Open Yapper to allow it.", isError: true, seconds: 4)
            openMainWindow?()
            return false
        }
        do {
            try recorder.start(deviceUID: MacSettings.inputDeviceUID)
        } catch {
            hud.showMessage(error.localizedDescription, isError: true, seconds: 4)
            return false
        }
        phase = .recording
        hud.showListening(handsFree: false)
        play("Tink")
        return true
    }

    func finishRecording() {
        guard phase == .recording else { return }
        let samples = recorder.stop()
        let rate = recorder.sampleRate
        let duration = Double(samples.count) / rate
        phase = .transcribing
        hud.showTranscribing()
        play("Pop")

        Task {
            let id = UUID()
            let choice = ModelChoice.current
            do {
                // A model that's still loading (just after launch, or right
                // after a download) is a few seconds away: worth waiting for.
                if choice.isParakeet, let loadTask { await loadTask.value }
                let output = try await transcriber.transcribe(
                    samples, sampleRate: rate, preferred: choice,
                    allowApple: !Settings.parakeetOnly,
                    fallbackReason: parakeetUnavailableReason(choice)
                )
                let text = TextProcessor.clean(output.text, options: Settings.processorOptions)
                if text.isEmpty {
                    let message = "Didn't catch anything. Try again a little closer to the mic."
                    saveFailure(id: id, message: message, samples: samples, rate: rate, duration: duration, output: output)
                    hud.showMessage(message, isError: true)
                } else {
                    let typed = TextInserter.needsLeadingSpace() ? " " + text : text
                    if TextInserter.insert(typed, keepOnClipboard: MacSettings.keepOnClipboard) {
                        hud.hide()
                    } else {
                        hud.showMessage("Copied. Press ⌘V to paste, or allow Accessibility so Yapper can.", seconds: 4)
                    }
                    lastText = text
                    HistoryStore.append(DictationRecord(
                        id: id, text: text, raw: output.text, duration: duration, engine: output.engine.rawValue,
                        model: output.model, processingTime: output.processingTime, note: output.note,
                        audioFile: RecordingStore.save(samples, sampleRate: rate, id: id)
                    ))
                    StatsStore.record(words: text.split(whereSeparator: \.isWhitespace).count, seconds: duration)
                }
            } catch Transcriber.TranscriberError.tooShort {
                hud.showMessage("Too short. Hold \(MacSettings.trigger.shortName) and talk.", seconds: 1.8)
            } catch {
                saveFailure(id: id, message: error.localizedDescription, samples: samples, rate: rate,
                            duration: duration, output: nil)
                hud.showMessage(error.localizedDescription, isError: true, seconds: 4)
            }
            RecordingStore.prune()
            historyVersion += 1
            phase = .idle
            if choice == .apple { await transcriber.prepareApple() }
        }
    }

    func cancelRecording() {
        guard phase == .recording else { return }
        _ = recorder.stop()
        gesture.reset()
        phase = .idle
        hud.showMessage("Cancelled", seconds: 1)
    }

    /// From the menu: the same as a tap of the key.
    func toggleFromMenu() {
        switch phase {
        case .idle:
            if startRecording() {
                _ = gesture.press(at: Self.now)
                _ = gesture.release(at: Self.now)
                hud.showListening(handsFree: true)
            }
        case .recording:
            gesture.reset()
            finishRecording()
        case .transcribing:
            break
        }
    }

    private func parakeetUnavailableReason(_ choice: ModelChoice) -> String {
        guard choice.isParakeet else { return "" }
        switch modelState {
        case .notDownloaded: return "\(choice.title) isn't downloaded yet."
        case let .failed(message): return "\(choice.title) couldn't load: \(message)"
        default: return "\(choice.title) wasn't ready."
        }
    }

    /// Failed dictations go in History too, with their audio.
    private func saveFailure(id: UUID, message: String, samples: [Float], rate: Double,
                             duration: TimeInterval, output: Transcriber.Output?) {
        HistoryStore.append(DictationRecord(
            id: id, text: "", raw: output?.text ?? "", duration: duration,
            engine: output?.engine.rawValue ?? (ModelChoice.current.isParakeet ? Engine.parakeetNeuralEngine.rawValue : Engine.apple.rawValue),
            model: output?.model ?? ModelChoice.current.title, processingTime: output?.processingTime,
            note: output?.note, error: message,
            audioFile: RecordingStore.save(samples, sampleRate: rate, id: id)
        ))
    }

    private func play(_ name: String) {
        guard MacSettings.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: Models

    func refreshModels() {
        downloadedModels = Set(ModelChoice.allCases.filter { $0.isParakeet && Transcriber.isDownloaded($0) })
    }

    func refreshApple() async {
        appleState = await AppleAnalyzer.state()
    }

    /// Loads the chosen Parakeet model into the Neural Engine, or frees it
    /// when Apple's model is chosen.
    func loadModel() async {
        let choice = ModelChoice.current
        guard choice.isParakeet else {
            await transcriber.unload()
            modelState = .ready
            await transcriber.prepareApple()
            return
        }
        guard Transcriber.isDownloaded(choice) else {
            modelState = .notDownloaded
            return
        }
        if let loadTask {
            await loadTask.value
            return
        }
        modelState = .loading
        let task = Task { @MainActor in
            do {
                try await transcriber.load(choice)
                modelState = .ready
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Downloads a Parakeet model (the only time Yapper goes online), then
    /// switches to it.
    func download(_ choice: ModelChoice) async {
        guard downloading == nil else { return }
        downloading = choice
        modelState = .downloading(progress: 0, label: "Starting download")
        defer { downloading = nil }
        do {
            try await transcriber.download(choice) { progress, label in
                Task { @MainActor in
                    MacDictation.shared.modelState = .downloading(progress: progress, label: label)
                }
            }
            refreshModels()
            ModelChoice.current = choice
            objectWillChange.send()
            await loadModel()
        } catch {
            modelState = .failed(error.localizedDescription)
        }
    }

    func select(_ choice: ModelChoice) async {
        ModelChoice.current = choice
        objectWillChange.send()
        await loadModel()
    }

    func delete(_ choice: ModelChoice) async {
        if ModelChoice.current == choice {
            ModelChoice.current = .apple
            await loadModel()
        }
        try? Transcriber.deleteModel(choice)
        refreshModels()
        objectWillChange.send()
    }

    /// Downloads Apple's own speech model for this Mac's language (macOS 26).
    func installAppleModel() async {
        guard #available(macOS 26.0, *) else { return }
        appleInstallProgress = 0
        defer { appleInstallProgress = nil }
        do {
            try await AppleAnalyzer.install { progress in
                Task { @MainActor in MacDictation.shared.appleInstallProgress = progress }
            }
        } catch {
            hud.showMessage(error.localizedDescription, isError: true, seconds: 4)
        }
        await refreshApple()
    }

    /// Whether Apple's model can run right now: the newer model when it's
    /// installed, otherwise the older recognizer, which needs permission.
    var appleReady: Bool {
        appleState == .installed || speechAuthorized
    }

    // MARK: History

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func delete(_ record: DictationRecord) {
        if let file = record.audioFile { try? FileManager.default.removeItem(at: RecordingStore.url(for: file)) }
        HistoryStore.save(HistoryStore.load().filter { $0.id != record.id })
        historyVersion += 1
    }

    func deleteAllHistory() {
        HistoryStore.save([])
        RecordingStore.deleteAll()
        historyVersion += 1
    }
}
