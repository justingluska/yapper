import AVFoundation
import Foundation

/// The audio of each dictation, kept on this iPhone for Settings › Keep
/// recordings (30 days by default) so it can be played back or transcribed
/// again, including dictations that failed. The text in History stays after
/// its recording is deleted. AAC in the app's own container,
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
        guard Settings.recordingHours != 0, !samples.isEmpty,
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

    /// Bytes on disk, 0 when the file is gone.
    static func size(of file: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: file).path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// The space all kept recordings take.
    static func totalSize() -> Int64 {
        HistoryStore.load().compactMap(\.audioFile).reduce(0) { $0 + size(of: $1) }
    }

    /// What keeping recordings for `hours` would delete right now, so
    /// Settings can say so before it happens.
    static func wouldDelete(keeping hours: Int, now: Date = Date()) -> (count: Int, bytes: Int64) {
        let doomed = HistoryStore.load().filter { record in
            guard let file = record.audioFile, exists(file) else { return false }
            return Retention.isExpired(record.date, hours: hours, now: now)
        }
        return (doomed.count, doomed.compactMap(\.audioFile).reduce(0) { $0 + size(of: $1) })
    }

    /// Deletes recordings older than the setting, and any file History no
    /// longer points at. Ages come from the History record, not the file.
    /// Returns whether any History entry lost its recording.
    @discardableResult
    static func prune(now: Date = Date()) -> Bool {
        let hours = Settings.recordingHours
        var records = HistoryStore.load()
        var changed = false
        for index in records.indices {
            guard let file = records[index].audioFile else { continue }
            if Retention.isExpired(records[index].date, hours: hours, now: now) || !exists(file) {
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
        return changed
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
