import AVFoundation
import Foundation

/// The audio of each dictation, kept on this iPhone for Settings › Keep
/// recordings (1 day by default) so it can be played back or transcribed
/// again, including dictations that failed. AAC in the app's own container,
/// never shared with the keyboard and excluded from iCloud backup.
enum RecordingStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Recordings", isDirectory: true)
    }

    static func url(for file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    static func exists(_ file: String?) -> Bool {
        guard let file else { return false }
        return FileManager.default.fileExists(atPath: url(for: file).path)
    }

    /// Saves mono samples captured at `sampleRate`. Returns the file name,
    /// or nil when recordings are off or the write failed.
    static func save(_ samples: [Float], sampleRate: Double, id: UUID) -> String? {
        guard Settings.recordingDays != 0, !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var dir = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)

            let file = "\(id.uuidString).m4a"
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let output = try AVAudioFile(forWriting: url(for: file), settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            try output.write(from: buffer)
            return file
        } catch {
            return nil
        }
    }

    /// Mono float samples and their sample rate, for transcribing again.
    static func load(_ file: String) throws -> (samples: [Float], sampleRate: Double) {
        let input = try AVAudioFile(forReading: url(for: file), commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try input.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        return (Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), format.sampleRate)
    }

    /// Deletes recordings older than the setting, and any file History no
    /// longer points at. Ages come from the History record, not the file.
    static func prune(now: Date = Date()) {
        let days = Settings.recordingDays
        var records = HistoryStore.load()
        var changed = false
        for index in records.indices {
            guard let file = records[index].audioFile else { continue }
            let expired = days == 0 || (days > 0 && records[index].date < now.addingTimeInterval(-Double(days) * 86_400))
            if expired || !exists(file) {
                try? FileManager.default.removeItem(at: url(for: file))
                records[index].audioFile = nil
                changed = true
            }
        }
        if changed { HistoryStore.save(records) }

        let kept = Set(records.compactMap(\.audioFile))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where !kept.contains(file) {
            try? FileManager.default.removeItem(at: url(for: file))
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
