import AVFoundation
import Foundation

/// Owns the microphone. While a session is live the engine keeps running
/// (that is what keeps the app alive in the background, with the audio
/// background mode), but samples are only kept between `begin()` and `end()`.
final class Recorder {
    enum RecorderError: LocalizedError {
        case noInput
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noInput: return "No microphone is available."
            case .permissionDenied: return "Yapper doesn't have microphone access. Turn it on in Settings › Yapper."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var capturing = false
    private(set) var sampleRate: Double = 48_000
    private(set) var isRunning = false

    /// Called on the audio thread, while capturing, with an RMS level in 0...1
    /// for every 10 ms of audio and when it was heard (`LevelFeed.now` time).
    var onLevel: ((Float, Double) -> Void)?
    /// Called on the main queue when the audio session is interrupted (a
    /// phone call) or the route changes so the engine stopped.
    var onInterrupted: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.isRunning = false
                self.onInterrupted?()
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // A route change (AirPods in or out) stops the engine and changes
            // the input format. Rebuild the tap and carry on.
            guard let self, self.isRunning else { return }
            self.isRunning = false
            do { try self.start() } catch { self.onInterrupted?() }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    static var permission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Configures the session and starts the engine (mic warm, nothing kept).
    func start() throws {
        guard !isRunning else { return }
        guard Recorder.permission == .granted else { throw RecorderError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        // mixWithOthers: music keeps playing while the mic is warm. A2DP, not
        // HFP, so AirPods keep their controls and sound quality.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
        // Without this, keyboard haptics die system-wide while recording.
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        sampleRate = format.sampleRate

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, when in
            self?.handle(buffer, at: when)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.withLock {
            capturing = false
            samples = []
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Starts keeping samples.
    func begin() {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            capturing = true
        }
    }

    /// Stops keeping samples and returns what was captured, at `sampleRate`.
    func end() -> [Float] {
        lock.withLock {
            capturing = false
            let captured = samples
            samples = []
            return captured
        }
    }

    private var lastBeat: TimeInterval = 0

    private func handle(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
        // The heartbeat comes from the audio thread: a backgrounded app's main
        // queue gets throttled, but the tap keeps firing as long as the
        // engine (and so the session) is alive.
        let now = Date().timeIntervalSince1970
        if now - lastBeat >= 1 {
            lastBeat = now
            Bridge.defaults.set(now, forKey: Bridge.Key.heartbeat)
        }
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let mono = UnsafeBufferPointer(start: channels[0], count: count)

        guard lock.withLock({ capturing }) else { return }

        publishLevels(mono, rate: buffer.format.sampleRate, at: when)

        lock.withLock {
            if capturing { samples.append(contentsOf: mono) }
        }
    }

    /// A level per 10 ms window rather than per buffer: iOS taps at least
    /// 100 ms at a time, and a level per buffer is a waveform at ten frames a
    /// second. Each is stamped with when its window was heard, so the reader
    /// can play them back evenly however they arrive.
    private func publishLevels(_ mono: UnsafeBufferPointer<Float>, rate: Double, at when: AVAudioTime) {
        guard let onLevel, rate > 0, !mono.isEmpty else { return }
        let now = LevelFeed.now
        let duration = Double(mono.count) / rate
        var start = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : now - duration
        // A host time from the future or long ago is a bad stamp, not audio.
        if start > now || now - start > 1 { start = now - duration }

        let window = max(1, Int(rate / 100))
        var offset = 0
        while offset < mono.count {
            let length = min(window, mono.count - offset)
            var sum: Float = 0
            for index in offset..<(offset + length) { sum += mono[index] * mono[index] }
            let rms = (sum / Float(length)).squareRoot()
            // Map roughly -50...0 dBFS onto 0...1 for the waveform.
            let db = 20 * log10(max(rms, 0.000_01))
            onLevel(max(0, min(1, (db + 50) / 50)), start + (Double(offset) + Double(length) / 2) / rate)
            offset += length
        }
    }
}
