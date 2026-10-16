import AVFoundation
import AudioToolbox
import CoreAudio

/// The microphone, on only while you dictate: macOS shows its orange
/// recording dot exactly as long as Yapper is listening, never in between.
final class MacRecorder {
    enum RecorderError: LocalizedError {
        case noInput
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noInput: return "No microphone is available."
            case .permissionDenied: return "Yapper doesn't have microphone access. Turn it on in System Settings › Privacy & Security › Microphone."
            }
        }
    }

    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var sampleRate: Double = 48_000

    /// Called on the audio thread with an RMS level in 0...1.
    var onLevel: ((Float) -> Void)?
    /// Called on the main queue when the microphone goes away mid-dictation.
    var onLost: (() -> Void)?

    private var observer: NSObjectProtocol?

    static var permission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    var isRunning: Bool { engine?.isRunning ?? false }

    /// Turns the microphone on and starts keeping samples. `deviceUID`
    /// picks a microphone; nil (or one that's unplugged) uses the system's.
    func start(deviceUID: String?) throws {
        guard Self.permission == .granted else { throw RecorderError.permissionDenied }
        stopEngine()

        // A fresh engine each time picks up whatever microphone is current.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let uid = deviceUID, var device = AudioInput.device(uid: uid), let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        sampleRate = format.sampleRate

        lock.withLock { samples.removeAll(keepingCapacity: true) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine

        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { [weak self] _ in
            // The microphone was unplugged or switched mid-dictation.
            self?.onLost?()
        }
    }

    /// Turns the microphone off and returns what it heard, at `sampleRate`.
    func stop() -> [Float] {
        stopEngine()
        return lock.withLock {
            let captured = samples
            samples = []
            return captured
        }
    }

    private func stopEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let mono = UnsafeBufferPointer(start: channels[0], count: count)

        var sum: Float = 0
        for sample in mono { sum += sample * sample }
        let rms = count > 0 ? (sum / Float(count)).squareRoot() : 0
        // Map roughly -50...0 dBFS onto 0...1 for the waveform.
        let db = 20 * log10(max(rms, 0.000_01))
        onLevel?(max(0, min(1, (db + 50) / 50)))

        lock.withLock { samples.append(contentsOf: mono) }
    }
}
