import ActivityKit
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The app side of a dictation session. It owns the microphone and the model,
/// answers the keyboard's signals, and keeps the shared state and the Live
/// Activity up to date.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum ModelState: Equatable {
        case notDownloaded
        /// On the device, not in memory: the engine is off. It loads when
        /// the engine turns on.
        case standby
        case downloading(progress: Double, label: String)
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Bridge.Phase = .idle
    @Published private(set) var modelState: ModelState = .notDownloaded
    @Published private(set) var level: Float = 0
    @Published private(set) var recordingStarted: Date?
    @Published private(set) var sessionEnds: Date?
    @Published private(set) var lastText: String?
    @Published var errorMessage: String?
    /// What the next dictation will run on.
    @Published private(set) var engine: Engine = .apple
    /// Which Parakeet models are on the device.
    @Published private(set) var downloadedModels: Set<ModelChoice> = []
    /// True while a finished recording waits for Parakeet to finish loading.
    @Published private(set) var waitingForModel = false
    /// Which step of loading the model we're on, and when loading began,
    /// while `modelState` is `.loading`.
    @Published private(set) var loadStage: Transcriber.LoadStage?
    @Published private(set) var loadStarted: Date?
    /// Bumped whenever History changes, so its views reload.
    @Published private(set) var historyVersion = 0
    /// True while a saved recording is being transcribed again.
    @Published private(set) var retranscribing = false
    /// Why the Live Activity (Dynamic Island, Lock Screen) isn't showing,
    /// when it isn't. Nil when it is, or when no session is on.
    @Published private(set) var liveActivityProblem: String?

    /// True from the start of a recording until the user leaves the
    /// listening screen (swiping back to the keyboard, or Close).
    @Published private(set) var presentingListening = false
    @Published private(set) var recordingSource: Source = .app

    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let signals = SignalObserver()
    private var expiry: Timer?
    private var activity: Activity<SessionAttributes>?
    private var lastLevelWrite: CFTimeInterval = 0
    /// The load in flight, shared by everyone who needs the model, so a
    /// dictation can wait for it instead of falling back.
    private var loadTask: Task<Void, Never>?

    enum Source { case keyboard, app }

    var isSessionLive: Bool { phase != .idle }

    private init() {
        recorder.onLevel = { [weak self] value in
            Task { @MainActor in self?.updateLevel(value) }
        }
        recorder.onInterrupted = { [weak self] in
            Task { @MainActor in self?.handleInterruption() }
        }
        // Only commands carrying a token from Yapper's own keyboard or widget
        // count; any app can post the notification itself.
        signals.observe(.start) { Bridge.accept(.start) { [weak self] in self?.keyboardStart() } }
        signals.observe(.stop) { Bridge.accept(.stop) { [weak self] in self?.finishRecording() } }
        signals.observe(.cancel) { Bridge.accept(.cancel) { [weak self] in self?.cancelRecording() } }
        signals.observe(.endSession) { Bridge.accept(.endSession) { [weak self] in self?.endSession() } }
        NotificationCenter.default.addObserver(forName: .yapperStartRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleStartRequest() }
        }
        // A previous run may have died mid-session; the keyboard must not
        // believe a stale phase.
        Bridge.phase = .idle
        Bridge.recordingStarted = nil
        Bridge.level = 0
        Bridge.sessionEnds = nil
    }

    // MARK: Model
    //
    // The model is only in memory while the engine is on (or while a saved
    // recording is transcribed again). Off means off: nothing loaded, no
    // "getting ready" in the background.

    func refreshDownloadedModels() {
        downloadedModels = Set(ModelChoice.allCases.filter { Transcriber.isDownloaded($0) })
    }

    /// Puts `modelState` in line with what's on the device, without loading
    /// anything. Called at launch and whenever Yapper comes to the front.
    func refreshModelState() {
        refreshDownloadedModels()
        if case .downloading = modelState { return }
        let choice = ModelChoice.current
        guard choice.isParakeet else {
            modelState = .ready
            engine = .apple
            return
        }
        guard Transcriber.isDownloaded(choice) else {
            modelState = .notDownloaded
            return
        }
        // While the engine is on (or a load or redo is running) the load
        // path owns the state.
        if isSessionLive || retranscribing || loadTask != nil {
            if modelState == .notDownloaded { modelState = .standby }
            return
        }
        modelState = .standby
    }

    /// True when turning the engine on will load a Parakeet model for the
    /// first time on this iPhone, which takes minutes rather than seconds.
    var needsFirstLoad: Bool {
        let choice = ModelChoice.current
        return choice.isParakeet && Transcriber.isDownloaded(choice) && modelState != .ready
            && !Settings.loadedModels.contains(choice.rawValue)
    }

    /// Loads the selected model if it's on the device. Safe to call from
    /// anywhere, any number of times: callers share one load.
    func loadModelIfDownloaded() async {
        refreshDownloadedModels()
        let choice = ModelChoice.current
        guard choice.isParakeet else {
            await transcriber.unload()
            modelState = .ready
            engine = .apple
            return
        }
        guard Transcriber.isDownloaded(choice) else {
            if case .downloading = modelState { return }
            modelState = .notDownloaded
            return
        }
        // Wait out a load already in flight (possibly of the other model),
        // then check again.
        while let running = loadTask {
            await running.value
        }
        guard modelState != .ready, ModelChoice.current == choice else { return }
        let task = Task {
            await performLoad(choice)
            loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func performLoad(_ choice: ModelChoice) async {
        modelState = .loading
        loadStarted = Date()
        loadStage = Transcriber.LoadStage(step: 0, total: Transcriber.LoadStage.total, label: "Starting")
        defer {
            loadStage = nil
            loadStarted = nil
        }
        do {
            try await transcriber.load(choice) { stage in
                Task { @MainActor [weak self] in
                    // Stages only move forward (FluidAudio reports some twice).
                    guard let self, let current = self.loadStage, stage.step > current.step else { return }
                    self.loadStage = stage
                }
            }
            // The user may have picked another model while this one loaded;
            // that selection runs its own load.
            guard ModelChoice.current == choice else { return }
            modelState = .ready
            engine = await transcriber.currentEngine
            Settings.loadedModels.insert(choice.rawValue)
        } catch {
            guard ModelChoice.current == choice else { return }
            modelState = .failed(error.localizedDescription)
        }
    }

    /// Takes the model out of memory once the engine is off and nothing
    /// else needs it.
    private func releaseModel() {
        Task {
            while let running = loadTask {
                await running.value
            }
            guard !isSessionLive, !retranscribing else { return }
            await transcriber.unload()
            refreshModelState()
        }
    }

    /// Downloads a model (making it the selected one). It loads when the
    /// engine turns on, or right away if the engine is already on.
    func downloadModel(_ choice: ModelChoice = ModelChoice.current) async {
        guard choice.isParakeet else { return }
        if case .downloading = modelState { return }
        if choice != ModelChoice.current { await selectModel(choice) }
        Settings.wantsModelDownload = true
        modelState = .downloading(progress: 0, label: "Starting download")
        // Downloads stop if iOS suspends the app, so keep it awake meanwhile.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        do {
            if !Transcriber.isDownloaded(choice) {
                try await transcriber.download(choice) { progress, label in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.modelState else { return }
                        self.modelState = .downloading(progress: progress, label: label)
                    }
                }
            }
        } catch {
            modelState = .failed(error.localizedDescription)
            refreshDownloadedModels()
            return
        }
        Settings.wantsModelDownload = false
        modelState = .standby
        refreshDownloadedModels()
        if isSessionLive { await loadModelIfDownloaded() }
    }

    /// Picks up a download the user asked for that iOS interrupted by
    /// suspending Yapper.
    func resumeDownloadIfWanted() {
        let choice = ModelChoice.current
        guard Settings.wantsModelDownload, choice.isParakeet, !Transcriber.isDownloaded(choice) else { return }
        if case .downloading = modelState { return }
        Task { await downloadModel(choice) }
    }

    /// After a CPU fallback, go back to the Neural Engine while we're in
    /// the foreground.
    func restoreNeuralEngine() async {
        guard engine == .parakeetCPU else { return }
        await transcriber.retryNeuralEngine()
        engine = await transcriber.currentEngine
    }

    /// Makes `choice` the model dictation uses, and loads it if the engine
    /// is on. Ignored during a download.
    func selectModel(_ choice: ModelChoice) async {
        if case .downloading = modelState { return }
        guard choice != ModelChoice.current || modelState != .ready else { return }
        ModelChoice.current = choice
        if choice == .apple {
            // Choosing Apple and "only use Parakeet" contradict each other.
            Settings.parakeetOnly = false
            _ = await AppleSpeech.requestPermission()
        }
        await transcriber.unload()
        engine = .apple
        modelState = .notDownloaded
        refreshModelState()
        if isSessionLive { await loadModelIfDownloaded() }
    }

    /// Removes a model from the device. Deleting the one in use switches to
    /// the other Parakeet model when that one is downloaded.
    func deleteModel(_ choice: ModelChoice) async {
        guard choice.isParakeet else { return }
        if case .downloading = modelState, choice == ModelChoice.current { return }
        if choice == ModelChoice.current {
            await transcriber.unload()
            modelState = .notDownloaded
            engine = .apple
            Settings.wantsModelDownload = false
        }
        try? Transcriber.deleteModel(choice)
        Settings.loadedModels.remove(choice.rawValue)
        refreshDownloadedModels()
        if choice == ModelChoice.current,
           let other = ModelChoice.allCases.first(where: { $0 != choice && $0.isParakeet && downloadedModels.contains($0) }) {
            await selectModel(other)
        }
    }

    /// Why Parakeet can't take the next dictation, in words for History and
    /// for errors. Nil when it can.
    var parakeetUnavailableReason: String? {
        let title = ModelChoice.current.title
        switch modelState {
        case .ready: return nil
        case .notDownloaded: return "\(title) isn't downloaded."
        case .standby: return "\(title) wasn't loaded."
        case .downloading: return "\(title) was still downloading."
        case .loading: return "\(title) was still loading."
        case let .failed(message): return "\(title) couldn't load (\(message))."
        }
    }

    // MARK: History

    /// Transcribes a saved recording again, with the selected model or with
    /// Apple's recognizer, and updates its History entry. The result is
    /// copied to the clipboard.
    func retranscribe(_ record: DictationRecord, using choice: ModelChoice) async -> DictationRecord {
        var updated = record
        guard let file = record.audioFile, RecordingStore.exists(file) else {
            updated.error = "The recording of this dictation is no longer on this iPhone."
            return updated
        }
        retranscribing = true
        defer {
            retranscribing = false
            if !isSessionLive { releaseModel() }
        }
        do {
            let audio = try RecordingStore.load(file)
            if choice.isParakeet { await loadModelIfDownloaded() }
            let output = try await transcriber.transcribe(
                audio.samples, sampleRate: audio.sampleRate, preferred: choice,
                allowApple: choice == .apple,
                fallbackReason: parakeetUnavailableReason ?? "Parakeet wasn't ready."
            )
            let text = TextProcessor.clean(output.text, options: Settings.processorOptions)
            if text.isEmpty {
                updated.error = "Didn't catch anything in this recording."
            } else {
                if record.failed { StatsStore.record(words: text.split(whereSeparator: \.isWhitespace).count, seconds: record.duration) }
                updated.text = text
                updated.raw = output.text
                updated.engine = output.engine.rawValue
                updated.model = output.model
                updated.processingTime = output.processingTime
                updated.note = output.note
                updated.error = nil
                Clipboard.copy(text)
            }
        } catch {
            updated.error = error.localizedDescription
        }
        HistoryStore.update(updated)
        historyVersion += 1
        return updated
    }

    func deleteAllHistory() {
        HistoryStore.save([])
        RecordingStore.deleteAll()
        historyVersion += 1
    }

    func historyChanged() {
        historyVersion += 1
    }

    // MARK: Session

    /// Starts recording if the keyboard or a shortcut asked for it just
    /// before opening Yapper. Called on `yapper://dictate`, when the app
    /// becomes active, and when an intent runs in-process. Anything else
    /// that opens the URL only brings Yapper to the front.
    func handleStartRequest() {
        guard let source = Bridge.takeStartRequest() else { return }
        guard startSession() else { return }
        beginRecording(source: source == .keyboard ? .keyboard : .app)
    }

    /// Warms the microphone and marks the session live. Returns false and
    /// shows an error when the microphone can't start.
    @discardableResult
    func startSession() -> Bool {
        if let refusal = parakeetOnlyRefusal() {
            report(refusal)
            return false
        }
        do {
            try recorder.start()
        } catch {
            errorMessage = error.localizedDescription
            Bridge.lastError = error.localizedDescription
            return false
        }
        if phase == .idle { setPhase(.ready) }
        extendSession()
        // The recorder's audio thread keeps the heartbeat fresh while the
        // engine runs; a timer here would claim we're alive when the mic
        // has died.
        beat()
        startActivity()
        // Start loading now, so the model is warm by the time the first
        // recording ends.
        Task { await loadModelIfDownloaded() }
        return true
    }

    /// With Parakeet only on, a session can't start without a downloaded
    /// model: every dictation would fail.
    private func parakeetOnlyRefusal() -> String? {
        guard Settings.parakeetOnly, !Transcriber.isDownloaded(ModelChoice.current) else { return nil }
        return "Parakeet only is on, but \(ModelChoice.current.title) isn't downloaded. Download it in Settings, or turn Parakeet only off."
    }

    func endSession() {
        if phase == .recording { _ = recorder.end() }
        recorder.stop()
        expiry?.invalidate()
        expiry = nil
        sessionEnds = nil
        Bridge.sessionEnds = nil
        recordingStarted = nil
        Bridge.recordingStarted = nil
        presentingListening = false
        level = 0
        Bridge.level = 0
        setPhase(.idle)
        endActivity()
        releaseModel()
    }

    private func extendSession() {
        expiry?.invalidate()
        let minutes = Settings.sessionMinutes
        guard minutes > 0 else {
            sessionEnds = nil
            Bridge.sessionEnds = nil
            return
        }
        let ends = Date().addingTimeInterval(Double(minutes) * 60)
        sessionEnds = ends
        Bridge.sessionEnds = ends
        expiry = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Never cut off someone mid-sentence; check again shortly.
                if self.phase == .recording || self.phase == .transcribing {
                    self.extendSession()
                } else {
                    self.endSession()
                }
            }
        }
    }

    private func beat() {
        Bridge.defaults.set(Date().timeIntervalSince1970, forKey: Bridge.Key.heartbeat)
    }

    // MARK: Recording

    private func keyboardStart() {
        guard phase == .ready || phase == .idle else { return }
        if phase == .idle {
            // iOS won't start the microphone from the background. Stay quiet
            // and let the keyboard fall back to opening Yapper. The exception
            // is the Yapper keyboard used inside Yapper itself.
            guard UIApplication.shared.applicationState == .active, startSession() else { return }
        }
        beginRecording(source: .keyboard)
    }

    func beginRecording(source: Source) {
        guard recorder.isRunning || startSession() else { return }
        guard phase == .ready else { return }
        recordingSource = source
        errorMessage = nil
        Bridge.lastError = nil
        recorder.begin()
        let now = Date()
        recordingStarted = now
        Bridge.recordingStarted = now
        presentingListening = true
        setPhase(.recording)
        Haptics.start()
    }

    func finishRecording() {
        guard phase == .recording else { return }
        let samples = recorder.end()
        let rate = recorder.sampleRate
        let duration = Double(samples.count) / rate
        recordingStarted = nil
        Bridge.recordingStarted = nil
        setPhase(.transcribing)

        Task {
            let id = UUID()
            let choice = ModelChoice.current
            do {
                // A downloaded model that is still loading (right after a
                // cold start from the keyboard, or the first load after a
                // download) is worth waiting for. Falling back to Apple here
                // is what made Parakeet look missing.
                if choice.isParakeet, Transcriber.isDownloaded(choice), modelState != .ready {
                    waitingForModel = true
                    await loadModelIfDownloaded()
                    waitingForModel = false
                }
                let output = try await transcriber.transcribe(
                    samples, sampleRate: rate, preferred: choice,
                    allowApple: !Settings.parakeetOnly,
                    fallbackReason: parakeetUnavailableReason ?? "Parakeet wasn't ready."
                )
                engine = output.engine
                let text = TextProcessor.clean(output.text, options: Settings.processorOptions)
                if !text.isEmpty {
                    if recordingSource == .keyboard {
                        // The keyboard types it; the clipboard keeps a copy
                        // to paste again anywhere.
                        Bridge.publish(text)
                        if Settings.copyEveryDictation { Clipboard.copy(text) }
                    } else {
                        Clipboard.copy(text)
                    }
                    lastText = text
                    Haptics.success()
                    HistoryStore.append(DictationRecord(
                        id: id, text: text, raw: output.text, duration: duration, engine: output.engine.rawValue,
                        model: output.model, processingTime: output.processingTime, note: output.note,
                        audioFile: RecordingStore.save(samples, sampleRate: rate, id: id)
                    ))
                    StatsStore.record(words: text.split(whereSeparator: \.isWhitespace).count, seconds: duration)
                } else {
                    let message = "Didn't catch anything. Try again a little closer to the mic."
                    saveFailure(id: id, message: message, samples: samples, rate: rate, duration: duration, output: output)
                    report(message)
                }
            } catch Transcriber.TranscriberError.tooShort {
                // An accidental double tap: nothing worth keeping.
                report(Transcriber.TranscriberError.tooShort.localizedDescription)
            } catch {
                saveFailure(id: id, message: error.localizedDescription, samples: samples, rate: rate, duration: duration, output: nil)
                report(error.localizedDescription)
            }
            RecordingStore.prune()
            historyVersion += 1
            if recordingSource == .keyboard, UIApplication.shared.applicationState == .background {
                presentingListening = false
            }
            // The session may have ended (or been interrupted) meanwhile.
            guard phase == .transcribing else { return }
            setPhase(.ready)
            extendSession()
        }
    }

    /// Failed dictations go in History too, with their audio, so they can be
    /// played back and transcribed again.
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

    func cancelRecording() {
        guard phase == .recording else { return }
        _ = recorder.end()
        recordingStarted = nil
        Bridge.recordingStarted = nil
        presentingListening = false
        setPhase(.ready)
    }

    /// The user closed the listening screen or went back to the keyboard.
    func markReturned() {
        presentingListening = false
    }

    private func report(_ message: String) {
        errorMessage = message
        Bridge.lastError = message
        Bridge.post(.stateChanged)
        Haptics.warning()
    }

    private func handleInterruption() {
        // A call or Siri took the microphone. Keep what was said so far, then
        // stay off: restarting on our own would bring the mic back with
        // nobody asking for it. The next mic tap starts a new session.
        if phase == .recording {
            finishRecording()
        }
        recorder.stop()
        expiry?.invalidate()
        expiry = nil
        setPhase(.idle)
        endActivity()
        releaseModel()
    }

    // MARK: Shared state

    private func setPhase(_ newPhase: Bridge.Phase) {
        phase = newPhase
        Bridge.phase = newPhase
        beat()
        Bridge.post(.stateChanged)
        updateActivity()
    }

    private func updateLevel(_ value: Float) {
        guard phase == .recording else { return }
        level = value
        let now = CACurrentMediaTime()
        if now - lastLevelWrite > 0.066 {
            lastLevelWrite = now
            Bridge.level = value
        }
    }

    // MARK: Live Activity

    private var activityState: SessionAttributes.ContentState {
        SessionAttributes.ContentState(
            phase: phase.rawValue,
            sessionEnds: sessionEnds,
            recordingStarted: recordingStarted,
            lastWords: lastText.map { $0.split(whereSeparator: \.isWhitespace).count } ?? 0
        )
    }

    private func startActivity() {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivityProblem = "Live Activities are off for Yapper. Turn them on in iOS Settings › Yapper › Live Activities to see the engine in the Dynamic Island."
            return
        }
        // Clean up any activity left behind by a previous launch.
        for old in Activity<SessionAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            activity = try Activity.request(
                attributes: SessionAttributes(),
                content: ActivityContent(state: activityState, staleDate: sessionEnds),
                pushType: nil
            )
            liveActivityProblem = nil
        } catch {
            liveActivityProblem = "The Dynamic Island couldn't start: \(error.localizedDescription)"
        }
    }

    private func updateActivity() {
        guard let activity else { return }
        let content = ActivityContent(state: activityState, staleDate: sessionEnds)
        Task { await activity.update(content) }
    }

    private func endActivity() {
        liveActivityProblem = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

enum Haptics {
    static func start() {
        guard Settings.haptics else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        guard Settings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard Settings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// The clipboard, this iPhone only: Universal Clipboard would hand every
/// dictation to your other devices, which "nothing leaves your iPhone" rules
/// out.
enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]], options: [.localOnly: true])
    }
}
