import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Speech

/// Speech-to-text engines Yapper can use. Everything runs on the device.
enum ModelChoice: String, CaseIterable, Identifiable, Hashable {
    /// Apple's on-device speech recognition: built in, starts instantly. The
    /// default, and the one Yapper recommends. SpeechAnalyzer on iOS 26+, the older recognizer before that.
    case apple
    /// Parakeet Ultra: Moondream's post-training of NVIDIA Parakeet TDT 0.6B v3, the most accurate, 632 MB.
    case ultra
    /// Parakeet v3: the previous default, 480 MB. Fallback if Ultra misbehaves.
    case v3

    var id: String { rawValue }

    var isParakeet: Bool { self != .apple }

    /// The FluidAudio model, for Parakeet choices.
    var version: AsrModelVersion? {
        switch self {
        case .ultra: return .ultra
        case .v3: return .v3
        case .apple: return nil
        }
    }

    var title: String {
        switch self {
        case .ultra: return "Parakeet Ultra"
        case .v3: return "Parakeet v3"
        case .apple: return "Apple on-device"
        }
    }

    var detail: String {
        switch self {
        case .ultra: return "Optional download. Can be more accurate, but takes a few seconds to load each time Yapper turns on. 25 languages."
        case .v3: return "The previous Parakeet. 25 languages, smaller download."
        case .apple: return "Recommended. Built into iOS: nothing to download, starts instantly, works offline."
        }
    }

    var downloadMB: Int {
        switch self {
        case .ultra: return 632
        case .v3: return 480
        case .apple: return 0
        }
    }

    /// Apple on-device unless the user picked something else. Installs from
    /// before Apple became the default kept their choice implicit, so one
    /// with a Parakeet model on the device keeps using it.
    static var current: ModelChoice {
        get {
            if let stored = ModelChoice(rawValue: Bridge.defaults.string(forKey: Settings.Key.modelChoice) ?? "") {
                return stored
            }
            let initial = [ModelChoice.ultra, .v3].first(where: Transcriber.isDownloaded) ?? .apple
            Bridge.defaults.set(initial.rawValue, forKey: Settings.Key.modelChoice)
            return initial
        }
        set { Bridge.defaults.set(newValue.rawValue, forKey: Settings.Key.modelChoice) }
    }
}

/// Runs Parakeet through FluidAudio on the Neural Engine, and falls back to
/// Apple's on-device recognizer until the Parakeet model is ready.
actor Transcriber {
    enum TranscriberError: LocalizedError {
        case noEngine
        case tooShort
        /// Parakeet only is on and Parakeet can't run; the reason says why.
        case parakeetUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .noEngine: return "Nothing can transcribe yet. Download the Parakeet model in Settings, or allow Speech Recognition for Yapper in iOS Settings."
            case .tooShort: return "That was too short to hear anything."
            case let .parakeetUnavailable(reason): return "\(reason) Parakeet only is on, so Yapper didn't use Apple's recognizer. Turn it off in Settings to allow that."
            }
        }
    }

    private var asr: AsrManager?
    private var loadedChoice: ModelChoice?
    /// Apple's newest model, readied for the next dictation
    /// (`AppleAnalyzer.Prepared`; iOS 26 types can't be stored directly).
    private var preparedApple: AnyObject?
    private let converter = AudioConverter()

    static let parakeetSampleRate: Double = 16_000

    /// Hugging Face commits the models are pinned to, so a change upstream
    /// can never silently swap the model under users.
    static let pinnedRevisions: [String: String] = [
        "FluidInference/parakeet-ultra-coreml": "95eaa59a39d4394f047a4dc5cce480388a60d1b6",
        "FluidInference/parakeet-tdt-0.6b-v3-coreml": "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe",
    ]

    /// Call once at launch, before anything touches FluidAudio: pins the
    /// model revisions and forbids network access. The only time Yapper goes
    /// online is `download(_:)`, which the user starts.
    static func configure() {
        ModelRegistry.revisionOverrides = pinnedRevisions
        ModelHub.offlineMode = true
    }

    /// A finished transcription and what produced it.
    struct Output {
        var text: String
        var engine: Engine
        var model: String?
        var processingTime: TimeInterval
        var note: String?
    }

    var isParakeetReady: Bool { asr != nil }

    /// The engine the next dictation will use.
    var currentEngine: Engine {
        guard asr != nil else { return .apple }
        return onCPU ? .parakeetCPU : .parakeetNeuralEngine
    }

    /// Why we're on the CPU, if we are.
    private var cpuReason: String?

    /// Where models live: Application Support, excluded from iCloud backup.
    static func modelDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    /// Apple's recognizer is always "downloaded": it's part of iOS.
    static func isDownloaded(_ choice: ModelChoice) -> Bool {
        guard let version = choice.version else { return true }
        return AsrModels.modelsExist(at: modelDirectory(for: version), version: version)
    }

    /// Downloads the model files. Progress is byte-level, 0...1.
    func download(_ choice: ModelChoice, onProgress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard let version = choice.version else { return }
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        try await AsrModels.download(version: version) { progress in
            let label: String
            switch progress.phase {
            case .listing: label = "Starting download"
            case .downloading: label = "Downloading"
            case .compiling: label = "Optimizing for this iPhone"
            }
            onProgress(progress.fractionCompleted, label)
        }
        Self.excludeFromBackup(Self.modelDirectory(for: version))
    }

    /// Loads a downloaded model into the Neural Engine, offline. The first
    /// load compiles the model for this device and takes a while; later
    /// loads are quick.
    /// A step of loading a model, for the progress shown while the engine
    /// starts. Core ML reports no percentage, so this is step-based: the four
    /// model parts in the order FluidAudio loads them, then a warm-up.
    struct LoadStage: Equatable, Sendable {
        var step: Int
        var total: Int
        var label: String

        static let total = 5

        static func forModelFile(_ name: String) -> LoadStage? {
            let lower = name.lowercased()
            if lower.contains("preprocessor") { return LoadStage(step: 1, total: total, label: "Audio front end") }
            if lower.contains("encoder") { return LoadStage(step: 2, total: total, label: "Encoder, the big part") }
            if lower.contains("decoder") { return LoadStage(step: 3, total: total, label: "Decoder") }
            if lower.contains("joint") { return LoadStage(step: 4, total: total, label: "Joint network") }
            return nil
        }

        static let warmUp = LoadStage(step: 5, total: total, label: "Warming up")
    }

    func load(_ choice: ModelChoice, onStage: (@Sendable (LoadStage) -> Void)? = nil) async throws {
        guard choice.isParakeet else {
            // Nothing to load; free the Neural Engine model if one is in memory.
            await unload()
            return
        }
        if loadedChoice == choice, asr != nil { return }
        let manager: AsrManager
        do {
            manager = try await makeManager(choice, cpuOnly: false, onStage: onStage)
        } catch {
            // iOS can refuse the Neural Engine (older chips, or a background
            // restriction); the CPU is slower but always there.
            manager = try await makeManager(choice, cpuOnly: true)
            onCPU = true
            cpuReason = "The Neural Engine couldn't load the model (\(error.localizedDescription)), so Parakeet runs on the CPU."
        }
        await asr?.cleanup()
        asr = manager
        loadedChoice = choice
        // One pass over silence so the first real dictation doesn't pay for
        // the model's warm-up.
        onStage?(.warmUp)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        _ = try? await manager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &state)
    }

    /// True once we've fallen back to CPU-only inference.
    private var onCPU = false

    private func makeManager(_ choice: ModelChoice, cpuOnly: Bool,
                             onStage: (@Sendable (LoadStage) -> Void)? = nil) async throws -> AsrManager {
        guard let version = choice.version else { throw TranscriberError.noEngine }
        let dir = Self.modelDirectory(for: version)
        let manager = AsrManager(config: .default)
        let models: AsrModels
        if cpuOnly {
            let cpu = MLModelConfiguration()
            cpu.computeUnits = .cpuOnly
            models = try await AsrModels.load(from: dir, configuration: cpu, version: version,
                                              encoderComputeUnits: .cpuOnly)
        } else {
            models = try await AsrModels.load(from: dir, version: version) { progress in
                if case let .compiling(name) = progress.phase, let stage = LoadStage.forModelFile(name) {
                    onStage?(stage)
                }
            }
        }
        try await manager.loadModels(models)
        return manager
    }

    func unload() async {
        await asr?.cleanup()
        asr = nil
        loadedChoice = nil
        onCPU = false
        cpuReason = nil
    }

    static func deleteModel(_ choice: ModelChoice) throws {
        guard let version = choice.version else { return }
        let dir = modelDirectory(for: version)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Readies Apple's newest model for the next dictation, so its first
    /// words don't wait for the model to start. Called when the engine turns
    /// on and after each dictation. If it fails, the dictation readies the
    /// model itself and reports any error then.
    func prepareApple() async {
        guard #available(iOS 26.0, *), preparedApple == nil,
              await AppleAnalyzer.state() == .installed,
              let prepared = try? await AppleAnalyzer.prepare(),
              preparedApple == nil
        else { return }
        preparedApple = prepared
    }

    /// Lets go of the readied Apple model, when the engine turns off.
    func releaseApple() {
        preparedApple = nil
    }

    /// The readied Apple model, for one dictation only: an analyzer takes
    /// one recording.
    private func takePreparedApple() -> AnyObject? {
        defer { preparedApple = nil }
        return preparedApple
    }

    /// Transcribes mono samples captured at `sampleRate`. When no Parakeet
    /// model is loaded, Apple's recognizer does the work if `allowApple`,
    /// and `fallbackReason` (why Parakeet wasn't ready) is recorded with it.
    func transcribe(_ samples: [Float], sampleRate: Double, preferred: ModelChoice,
                    allowApple: Bool, fallbackReason: String) async throws -> Output {
        guard Double(samples.count) / sampleRate >= 0.3 else { throw TranscriberError.tooShort }
        let started = Date()

        if preferred == .apple {
            let (text, engine) = try await AppleSpeech.transcribe(samples, sampleRate: sampleRate,
                                                                  prepared: takePreparedApple())
            return Output(text: text, engine: engine, model: ModelChoice.apple.title,
                          processingTime: Date().timeIntervalSince(started), note: nil)
        }

        guard let asr, let choice = loadedChoice else {
            guard allowApple else { throw TranscriberError.parakeetUnavailable(fallbackReason) }
            let (text, engine) = try await AppleSpeech.transcribe(samples, sampleRate: sampleRate,
                                                                  prepared: takePreparedApple())
            return Output(text: text, engine: engine, model: nil, processingTime: Date().timeIntervalSince(started),
                          note: fallbackReason)
        }

        var audio = sampleRate == Self.parakeetSampleRate
            ? samples
            : try converter.resample(samples, from: sampleRate)
        // Parakeet's decoder drops words from clips under ~1.5 s; pad
        // short ones with silence.
        let minimum = max(24_000, ASRConstants.minimumRequiredSamples(forSampleRate: Int(Self.parakeetSampleRate)))
        if audio.count < minimum {
            audio += [Float](repeating: 0, count: minimum - audio.count)
        }

        do {
            let text = try await run(asr, audio)
            return Output(text: text, engine: onCPU ? .parakeetCPU : .parakeetNeuralEngine, model: choice.title,
                          processingTime: Date().timeIntervalSince(started), note: onCPU ? cpuReason : nil)
        } catch {
            // iOS 27 cancels Neural Engine work from backgrounded apps
            // that lack the Background Inference entitlement. Retry once
            // on the CPU rather than lose the dictation.
            guard !onCPU else { throw error }
            let cpu = try await makeManager(choice, cpuOnly: true)
            await asr.cleanup()
            self.asr = cpu
            onCPU = true
            cpuReason = "iOS refused the Neural Engine (\(error.localizedDescription)), so Parakeet switched to the CPU."
            let text = try await run(cpu, audio)
            return Output(text: text, engine: .parakeetCPU, model: choice.title,
                          processingTime: Date().timeIntervalSince(started), note: cpuReason)
        }
    }

    /// Goes back to the Neural Engine after a CPU fallback, next time the
    /// app is in the foreground (where iOS always allows it).
    func retryNeuralEngine() async {
        guard onCPU, let choice = loadedChoice,
              let manager = try? await makeManager(choice, cpuOnly: false) else { return }
        await asr?.cleanup()
        asr = manager
        onCPU = false
        cpuReason = nil
    }

    private func run(_ manager: AsrManager, _ audio: [Float]) async throws -> String {
        // A fresh decoder state per dictation, or the previous one's context
        // leaks into this one.
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(audio, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

/// Apple's on-device speech recognition. On iOS 26 and later that's
/// SpeechAnalyzer, the newer, faster model behind Notes and Voice Memos
/// transcription, when its files are on this iPhone. Otherwise it's the older
/// recognizer, forced to run on the device.
enum AppleSpeech {
    static var isAvailable: Bool {
        guard let recognizer = SFSpeechRecognizer() else { return false }
        return recognizer.supportsOnDeviceRecognition && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// Transcribes with the newer model when it can, the older one otherwise,
    /// and says which one did it. `prepared` is a readied
    /// `AppleAnalyzer.Prepared`, when there is one.
    static func transcribe(_ samples: [Float], sampleRate: Double,
                           prepared: AnyObject? = nil) async throws -> (text: String, engine: Engine) {
        if #available(iOS 26.0, *) {
            if let prepared = prepared as? AppleAnalyzer.Prepared {
                return (try await AppleAnalyzer.transcribe(samples, sampleRate: sampleRate, prepared: prepared), .appleAnalyzer)
            }
            if await AppleAnalyzer.state() == .installed {
                return (try await AppleAnalyzer.transcribe(samples, sampleRate: sampleRate), .appleAnalyzer)
            }
        }
        return (try await recognize(samples, sampleRate: sampleRate), .apple)
    }

    /// The older recognizer. Apple documents it as stopping after a minute of
    /// audio, so a longer dictation goes through in pieces, cut at pauses.
    private static func recognize(_ samples: [Float], sampleRate: Double) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition,
              SFSpeechRecognizer.authorizationStatus() == .authorized
        else { throw Transcriber.TranscriberError.noEngine }

        var pieces: [String] = []
        for range in AudioChunks.split(samples, sampleRate: sampleRate) {
            guard let buffer = AppleAnalyzer.buffer(Array(samples[range]), sampleRate: sampleRate)
            else { throw Transcriber.TranscriberError.noEngine }
            do {
                let text = try await recognize(buffer, with: recognizer)
                if !text.isEmpty { pieces.append(text) }
            } catch where isNoSpeech(error as NSError) && range.count < samples.count {
                // A piece that's all pause (a long think mid-dictation).
                // The rest still counts; a recording that's silent
                // throughout still fails as before.
                continue
            }
        }
        return pieces.joined(separator: " ")
    }

    /// The recognizer's "No speech detected" error.
    private static func isNoSpeech(_ error: NSError) -> Bool {
        error.domain == "kAFAssistantErrorDomain" && error.code == 1110
    }

    private static func recognize(_ buffer: AVAudioPCMBuffer, with recognizer: SFSpeechRecognizer) async throws -> String {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.append(buffer)
        request.endAudio()

        let text: String = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Apple's SpeechAnalyzer model (iOS 26+). iOS keeps its files, shared by
/// every app; when they aren't on this iPhone for its language, iOS
/// downloads them from Apple when the user asks.
enum AppleAnalyzer {
    enum State: Equatable {
        /// Older iOS, or no model for this iPhone's language.
        case unsupported
        case notInstalled
        case installed
    }

    enum AnalyzerError: LocalizedError {
        case unavailable
        case audioFormat

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple's newer speech model isn't on this iPhone."
            case .audioFormat: return "Apple's speech model couldn't read this audio."
            }
        }
    }

    static func state() async -> State {
        guard #available(iOS 26.0, *) else { return .unsupported }
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        else { return .unsupported }
        let installed = await SpeechTranscriber.installedLocales
        let id = locale.identifier(.bcp47)
        return installed.contains { $0.identifier(.bcp47) == id } ? .installed : .notInstalled
    }

    /// Asks iOS to download the model for this iPhone's language. `onProgress`
    /// gets 0...1. The download is Apple's, between iOS and Apple, like the
    /// files for the system's own dictation; no audio is involved.
    @available(iOS 26.0, *)
    static func install(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw AnalyzerError.unavailable
        }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber(locale)])
        else { return }
        let progress = request.progress
        let watcher = Task {
            while !Task.isCancelled {
                onProgress(progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
        onProgress(1)
    }

    @available(iOS 26.0, *)
    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    /// An analyzer with its model started, ready for one recording.
    @available(iOS 26.0, *)
    final class Prepared {
        let transcriber: SpeechTranscriber
        let analyzer: SpeechAnalyzer
        let format: AVAudioFormat

        init(transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer, format: AVAudioFormat) {
            self.transcriber = transcriber
            self.analyzer = analyzer
            self.format = format
        }
    }

    /// Starts the model now instead of when the first audio arrives
    /// (`prepareToAnalyze`), the way Apple recommends for a quick first
    /// result. `lingering` keeps the model in memory for a while after the
    /// analyzer is done, so the next dictation's analyzer doesn't start it
    /// again from scratch; iOS frees it when Yapper stops using it.
    @available(iOS 26.0, *)
    static func prepare() async throws -> Prepared {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw AnalyzerError.unavailable
        }
        let transcriber = makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: .init(priority: .userInitiated, modelRetention: .lingering))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AnalyzerError.audioFormat
        }
        try await analyzer.prepareToAnalyze(in: format)
        return Prepared(transcriber: transcriber, analyzer: analyzer, format: format)
    }

    /// There is no length limit to plan for: SpeechAnalyzer is built for
    /// long audio (Notes and Voice Memos transcribe whole recordings with it).
    @available(iOS 26.0, *)
    static func transcribe(_ samples: [Float], sampleRate: Double, prepared: Prepared? = nil) async throws -> String {
        let session: Prepared
        if let prepared {
            session = prepared
        } else {
            session = try await prepare()
        }
        let transcriber = session.transcriber
        let analyzer = session.analyzer
        guard let source = buffer(samples, sampleRate: sampleRate),
              let audio = convert(source, to: session.format)
        else { throw AnalyzerError.audioFormat }

        // Collect results as they finalize; the sequence ends when the
        // analyzer finishes.
        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        input.yield(AnalyzerInput(buffer: audio))
        input.finish()
        if let end = try await analyzer.analyzeSequence(stream) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mono float samples as an audio buffer.
    static func buffer(_ samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// Converts a buffer to the format the analyzer wants, in one pass.
    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return nil }
        return output
    }
}
