import Foundation
import UIKit

/// Writes exports to a temporary folder for the share sheet, and reads a
/// Yapper JSON export (with any recordings picked alongside it) back into
/// History. Everything stays on this iPhone until the user shares it.
enum HistoryTransfer {
    /// Every export gets its own folder in here, deleted after sharing and
    /// on the next launch in case Yapper was closed mid-share.
    static var exportsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    /// Writes the export file and, when asked, the recordings next to it.
    /// Returns the files to share, the export file first.
    static func prepare(_ records: [DictationRecord], as format: HistoryExport.Format,
                        includeRecordings: Bool, now: Date = Date()) throws -> [URL] {
        let folder = exportsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var names: [UUID: String] = [:]
        var audio: [URL] = []
        if includeRecordings {
            var taken = Set<String>()
            for record in records {
                guard let file = record.audioFile, RecordingStore.exists(file) else { continue }
                let name = HistoryExport.recordingName(for: record, taken: taken)
                let target = folder.appendingPathComponent(name)
                // A hard link costs no space and no time; copy if iOS won't link.
                do {
                    try FileManager.default.linkItem(at: RecordingStore.url(for: file), to: target)
                } catch {
                    try FileManager.default.copyItem(at: RecordingStore.url(for: file), to: target)
                }
                taken.insert(name)
                names[record.id] = name
                audio.append(target)
            }
        }

        // JSON carries stats too, so moving to a new iPhone keeps them.
        let stats = format == .json ? StatsStore.load() : nil
        let file = folder.appendingPathComponent(HistoryExport.fileName(format, now: now))
        try HistoryExport.data(records, as: format, recordings: names, stats: stats, now: now)
            .write(to: file, options: .atomic)
        return [file] + audio
    }

    /// One dictation's recording under a readable name, for sharing it alone.
    static func prepareRecording(of record: DictationRecord) throws -> URL {
        guard let file = record.audioFile, RecordingStore.exists(file) else { throw CocoaError(.fileNoSuchFile) }
        let folder = exportsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(HistoryExport.recordingName(for: record, taken: []))
        do {
            try FileManager.default.linkItem(at: RecordingStore.url(for: file), to: target)
        } catch {
            try FileManager.default.copyItem(at: RecordingStore.url(for: file), to: target)
        }
        return target
    }

    /// Deletes an export's folder once it has been shared (or not).
    static func cleanUp(_ files: [URL]) {
        guard let folder = files.first?.deletingLastPathComponent(),
              folder.deletingLastPathComponent().standardizedFileURL == exportsDirectory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes every leftover export.
    static func cleanUpAll() {
        try? FileManager.default.removeItem(at: exportsDirectory)
    }

    // MARK: Import

    struct ImportResult {
        var added = 0
        var alreadyHere = 0
        /// Imported dictations older than Keep text, left out.
        var tooOld = 0
        var recordings = 0
    }

    /// Reads the picked files: one Yapper JSON export, plus any of the
    /// recordings exported with it. Merges by id, so nothing is added twice.
    static func importFiles(_ urls: [URL]) throws -> ImportResult {
        var json: Data?
        var audio: [String: URL] = [:]
        var accessed: [URL] = []
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        for url in urls {
            if url.startAccessingSecurityScopedResource() { accessed.append(url) }
            if url.pathExtension.lowercased() == "json" {
                guard json == nil else { throw TransferError.severalExports }
                json = try Data(contentsOf: url)
            } else {
                audio[url.lastPathComponent] = url
            }
        }
        guard let json else { throw TransferError.noExport }

        let archive = try HistoryExport.decode(json)
        let existing = HistoryStore.load()
        var (merged, added) = HistoryExport.merge(existing, archive.records)

        // Keep text applies to imports too, so nothing vanishes later.
        let kept = HistoryStore.prune(merged)
        let keptIDs = Set(kept.map(\.id))
        var result = ImportResult()
        result.alreadyHere = archive.records.count - added.count
        result.tooOld = added.filter { !keptIDs.contains($0.id) }.count
        added = added.filter { keptIDs.contains($0.id) }
        result.added = added.count

        // Each imported record points at its recording by the exported file
        // name; bring the ones that were picked into Yapper's own folder.
        let addedIDs = Set(added.map(\.id))
        merged = kept
        for index in merged.indices where addedIDs.contains(merged[index].id) {
            let exportedName = merged[index].audioFile
            merged[index].audioFile = nil
            guard let exportedName, let source = audio[exportedName] else { continue }
            let file = "\(merged[index].id.uuidString).m4a"
            try? FileManager.default.createDirectory(at: RecordingStore.directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: RecordingStore.url(for: file))
            if (try? FileManager.default.copyItem(at: source, to: RecordingStore.url(for: file))) != nil {
                merged[index].audioFile = file
            }
        }
        RecordingStore.excludeFromBackup()

        HistoryStore.save(merged)
        if let stats = archive.stats { StatsStore.merge(stats) }
        // Keep recordings applies too.
        RecordingStore.prune()
        let after = Set(HistoryStore.load().filter { addedIDs.contains($0.id) }.compactMap(\.audioFile))
        result.recordings = after.count
        return result
    }

    enum TransferError: LocalizedError {
        case noExport
        case severalExports

        var errorDescription: String? {
            switch self {
            case .noExport: return "Pick the JSON file from a Yapper export. You can pick its recordings along with it."
            case .severalExports: return "Pick one JSON export at a time."
            }
        }
    }
}

/// The iOS share sheet: AirDrop, Save to Files, Messages, Mail and the rest.
@MainActor
enum ShareSheet {
    /// Shows the share sheet over whatever is on screen. `completion` gets
    /// whether something was actually shared.
    static func present(_ items: [Any], completion: @escaping (Bool) -> Void = { _ in }) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return completion(false) }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }

        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Copy from the share sheet would use Universal Clipboard and hand the
        // text to your other devices; Yapper's own Copy stays on this iPhone.
        sheet.excludedActivityTypes = [.copyToPasteboard]
        sheet.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        top.present(sheet, animated: true)
    }
}
