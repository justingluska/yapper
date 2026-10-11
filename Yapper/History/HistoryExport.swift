import Foundation

/// Turning History into files someone can keep, and a Yapper JSON export back
/// into History. Pure Foundation, no file system and no network, so the unit
/// tests cover all of it.
enum HistoryExport {
    enum Format: String, CaseIterable, Identifiable {
        case text, markdown, json, csv

        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: return "Plain text"
            case .markdown: return "Markdown"
            case .json: return "JSON"
            case .csv: return "CSV"
            }
        }

        var detail: String {
            switch self {
            case .text: return "Date and words. Opens anywhere."
            case .markdown: return "For notes apps that read Markdown."
            case .json: return "Everything, to import into Yapper on another iPhone."
            case .csv: return "A table for Numbers, Excel or Google Sheets."
            }
        }

        var fileExtension: String {
            switch self {
            case .text: return "txt"
            case .markdown: return "md"
            case .json: return "json"
            case .csv: return "csv"
            }
        }
    }

    /// The JSON file: versioned so a later Yapper can still read it.
    struct Archive: Codable {
        static let formatName = "yapper.history"
        static let currentVersion = 1

        var format = Self.formatName
        var version = Self.currentVersion
        var exportedAt: Date
        var records: [DictationRecord]
        /// Stats per day ("yyyy-MM-dd"), so moving to a new iPhone keeps them.
        var stats: [String: DayTotals]?
    }

    enum ImportError: LocalizedError, Equatable {
        case notYapper
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notYapper:
                return "That file isn't a Yapper JSON export. In Yapper, export History as JSON and import that file."
            case .newerVersion:
                return "That export comes from a newer Yapper. Update Yapper on this iPhone and try again."
            }
        }
    }

    // MARK: Writing

    /// The file's contents. `recordings` maps a record id to the name of its
    /// audio file in the same export, when recordings go along.
    static func data(_ records: [DictationRecord], as format: Format, recordings: [UUID: String] = [:],
                     stats: [String: DayTotals]? = nil, now: Date = Date(), timeZone: TimeZone = .current) -> Data {
        switch format {
        case .text: return Data(text(records, recordings: recordings, now: now, timeZone: timeZone).utf8)
        case .markdown: return Data(markdown(records, recordings: recordings, now: now, timeZone: timeZone).utf8)
        case .csv: return Data(csv(records, recordings: recordings).utf8)
        case .json: return json(records, recordings: recordings, stats: stats, now: now)
        }
    }

    static func text(_ records: [DictationRecord], recordings: [UUID: String] = [:],
                     now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var lines = ["Yapper history", "\(count(records.count)), exported \(readable(now, timeZone))"]
        for record in records {
            lines.append("")
            lines.append(readable(record.date, timeZone))
            lines.append(record.error.map { "Failed: \($0)" } ?? record.text)
            if let file = recordings[record.id] { lines.append("Recording: \(file)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func markdown(_ records: [DictationRecord], recordings: [UUID: String] = [:],
                         now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var lines = ["# Yapper history", "", "\(count(records.count)), exported \(readable(now, timeZone))."]
        for record in records {
            lines += ["", "## \(readable(record.date, timeZone))", ""]
            lines.append(record.error.map { "**Failed:** \($0)" } ?? record.text)
            var meta = [record.engineLabel, String(format: "%.1f s", record.duration)]
            if let file = recordings[record.id] {
                let link = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
                meta.append("[Recording](\(link))")
            }
            lines += ["", "_\(meta.joined(separator: " · "))_"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let csvHeader = ["date", "text", "words", "duration_seconds", "engine", "model",
                            "failed", "error", "note", "before_cleanup", "recording", "id"]

    /// RFC 4180: comma-separated, CRLF line ends, fields with a comma, quote
    /// or line break quoted, quotes doubled. Starts with a byte-order mark so
    /// Excel reads it as UTF-8.
    static func csv(_ records: [DictationRecord], recordings: [UUID: String] = [:]) -> String {
        let iso = ISO8601DateFormatter()
        var rows = [csvHeader]
        for record in records {
            rows.append([
                iso.string(from: record.date),
                record.text,
                String(record.wordCount),
                String(format: "%.1f", record.duration),
                record.engineLabel,
                record.model ?? "",
                record.failed ? "yes" : "no",
                record.error ?? "",
                record.note ?? "",
                record.raw == record.text ? "" : record.raw,
                recordings[record.id] ?? "",
                record.id.uuidString,
            ])
        }
        return "\u{FEFF}" + rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func json(_ records: [DictationRecord], recordings: [UUID: String] = [:],
                     stats: [String: DayTotals]? = nil, now: Date = Date()) -> Data {
        let exported = records.map { record -> DictationRecord in
            var copy = record
            copy.audioFile = recordings[record.id]
            return copy
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(Archive(exportedAt: now, records: exported, stats: stats))) ?? Data()
    }

    /// "Yapper history 2026-10-11.txt"
    static func fileName(_ format: Format, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        "Yapper history \(stamp(now, timeZone, time: false)).\(format.fileExtension)"
    }

    /// "Yapper 2026-10-11 09.30.12.m4a", unique within `taken`.
    static func recordingName(for record: DictationRecord, taken: Set<String>, timeZone: TimeZone = .current) -> String {
        let base = "Yapper \(stamp(record.date, timeZone, time: true))"
        var name = "\(base).m4a"
        var number = 2
        while taken.contains(name) {
            name = "\(base) (\(number)).m4a"
            number += 1
        }
        return name
    }

    // MARK: Reading

    /// Records (and stats, when present) from a Yapper JSON export. Also reads
    /// a bare list of records, the shape of Yapper's own history file.
    static func decode(_ data: Data) throws -> Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let archive = try? decoder.decode(Archive.self, from: data) {
            guard archive.format == Archive.formatName else { throw ImportError.notYapper }
            guard archive.version <= Archive.currentVersion else { throw ImportError.newerVersion(archive.version) }
            return archive
        }
        // A newer export may add fields this version can't read; say so
        // rather than calling it "not Yapper".
        if let header = try? decoder.decode(Header.self, from: data), header.format == Archive.formatName {
            throw header.version > Archive.currentVersion ? ImportError.newerVersion(header.version) : ImportError.notYapper
        }
        if let records = try? decoder.decode([DictationRecord].self, from: data) {
            return Archive(exportedAt: Date(), records: records, stats: nil)
        }
        throw ImportError.notYapper
    }

    private struct Header: Decodable {
        var format: String
        var version: Int
    }

    /// `existing` plus every imported record it doesn't already have (by id),
    /// newest first. Records already here are left exactly as they are.
    static func merge(_ existing: [DictationRecord], _ incoming: [DictationRecord])
        -> (records: [DictationRecord], added: [DictationRecord]) {
        var seen = Set(existing.map(\.id))
        var added: [DictationRecord] = []
        for record in incoming where !seen.contains(record.id) {
            seen.insert(record.id)
            added.append(record)
        }
        let merged = (existing + added).enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map { $0.element }
        return (merged, added)
    }

    // MARK: Helpers

    private static func count(_ n: Int) -> String {
        n == 1 ? "1 dictation" : "\(n) dictations"
    }

    private static func readable(_ date: Date, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func stamp(_ date: Date, _ timeZone: TimeZone, time: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = time ? "yyyy-MM-dd HH.mm.ss" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
