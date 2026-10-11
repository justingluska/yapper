import AVFoundation

/// Writes mono float samples to an AAC (.m4a) file. Kept apart from
/// RecordingStore so the tests can check every microphone sample rate.
enum RecordingEncoder {
    /// 64 kbps for the built-in microphone (44.1 and 48 kHz). AAC refuses
    /// that rate below about 22 kHz, which is what Bluetooth headsets record
    /// at (16 kHz, or 8 kHz on older ones): there it's two bits a sample.
    static func bitRate(sampleRate: Double) -> Int {
        min(64_000, Int(sampleRate * 2))
    }

    static func settings(sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate(sampleRate: sampleRate),
        ]
    }

    static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { throw CocoaError(.fileWriteUnknown) }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let output = try AVAudioFile(forWriting: url, settings: settings(sampleRate: sampleRate),
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        try output.write(from: buffer)
    }
}
