import XCTest

final class HistoryExportTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ text: String, hoursAgo: Double = 0, error: String? = nil, audio: String? = nil) -> DictationRecord {
        DictationRecord(date: now.addingTimeInterval(-hoursAgo * 3_600), text: text, raw: text, duration: 2.5,
                        engine: Engine.appleAnalyzer.rawValue, model: "Apple on-device", processingTime: 0.2,
                        error: error, audioFile: audio)
    }

    // MARK: CSV

    func testCSVFieldsThatNeedNoQuotes() {
        XCTAssertEqual(HistoryExport.csvField("plain words"), "plain words")
        XCTAssertEqual(HistoryExport.csvField(""), "")
    }

    func testCSVQuotesCommasQuotesAndLineBreaks() {
        XCTAssertEqual(HistoryExport.csvField("milk, eggs"), "\"milk, eggs\"")
        XCTAssertEqual(HistoryExport.csvField("she said \"hi\""), "\"she said \"\"hi\"\"\"")
        XCTAssertEqual(HistoryExport.csvField("one\ntwo"), "\"one\ntwo\"")
        XCTAssertEqual(HistoryExport.csvField("one\r\ntwo"), "\"one\r\ntwo\"")
        XCTAssertEqual(HistoryExport.csvField("one\rtwo"), "\"one\rtwo\"")
    }

    func testCSVRowsAndHeader() {
        let first = record("Hello, \"world\"")
        let failed = record("", hoursAgo: 1, error: "Didn't catch anything.")
        let csv = HistoryExport.csv([first, failed], recordings: [first.id: "Yapper 1.m4a"])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}date,text,words,"))
        let lines = csv.dropFirst().components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 4) // header, two rows, and the empty string after the last CRLF
        XCTAssertEqual(lines.last, "")
        XCTAssertTrue(lines[1].contains(",\"Hello, \"\"world\"\"\",2,2.5,"))
        XCTAssertTrue(lines[1].contains(",Yapper 1.m4a,\(first.id.uuidString)"))
        XCTAssertTrue(lines[2].contains(",yes,Didn't catch anything.,"))
        // Every row has as many fields as the header.
        XCTAssertEqual(lines[2].components(separatedBy: ",").count, HistoryExport.csvHeader.count)
    }

    // MARK: Text and Markdown

    func testPlainTextHasEveryDictation() {
        let text = HistoryExport.text([record("First one"), record("", hoursAgo: 2, error: "No speech")],
                                      now: now, timeZone: utc)
        XCTAssertTrue(text.hasPrefix("Yapper history\n2 dictations, exported "))
        XCTAssertTrue(text.contains("\nFirst one\n"))
        XCTAssertTrue(text.contains("\nFailed: No speech\n"))
    }

    func testMarkdownLinksRecordings() {
        let first = record("With audio")
        let markdown = HistoryExport.markdown([first], recordings: [first.id: "Yapper 2026-01-15 08.00.00.m4a"],
                                              now: now, timeZone: utc)
        XCTAssertTrue(markdown.hasPrefix("# Yapper history\n"))
        XCTAssertTrue(markdown.contains("\nWith audio\n"))
        XCTAssertTrue(markdown.contains("[Recording](Yapper%202026-01-15%2008.00.00.m4a)"))
    }

    func testRecordingNamesAreUnique() {
        let one = record("a")
        let first = HistoryExport.recordingName(for: one, taken: [], timeZone: utc)
        XCTAssertEqual(first, "Yapper 2027-01-15 08.00.00.m4a")
        XCTAssertEqual(HistoryExport.recordingName(for: one, taken: [first], timeZone: utc), "Yapper 2027-01-15 08.00.00 (2).m4a")
    }

    // MARK: JSON

    func testJSONRoundTrip() throws {
        let records = [record("One"), record("Two", hoursAgo: 3, audio: "abc.m4a"), record("", hoursAgo: 5, error: "Oops")]
        let stats = ["2027-01-15": DayTotals(words: 12, dictations: 2, seconds: 7.5)]
        let data = HistoryExport.json(records, recordings: [records[1].id: "Yapper two.m4a"], stats: stats, now: now)
        let archive = try HistoryExport.decode(data)
        XCTAssertEqual(archive.format, "yapper.history")
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.exportedAt, now)
        XCTAssertEqual(archive.stats, stats)
        XCTAssertEqual(archive.records.map(\.id), records.map(\.id))
        XCTAssertEqual(archive.records.map(\.text), ["One", "Two", ""])
        XCTAssertEqual(archive.records[2].error, "Oops")
        XCTAssertEqual(archive.records[0].date, records[0].date)
        // Recordings are named as they are in the export, or not at all.
        XCTAssertNil(archive.records[0].audioFile)
        XCTAssertEqual(archive.records[1].audioFile, "Yapper two.m4a")
    }

    func testDecodeReadsABareHistoryFile() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([record("Raw history")])
        XCTAssertEqual(try HistoryExport.decode(data).records.map(\.text), ["Raw history"])
    }

    func testDecodeRejectsOtherFiles() {
        XCTAssertThrowsError(try HistoryExport.decode(Data("{\"hello\": 1}".utf8))) { error in
            XCTAssertEqual(error as? HistoryExport.ImportError, .notYapper)
        }
        XCTAssertThrowsError(try HistoryExport.decode(Data("not json".utf8)))
    }

    func testDecodeRejectsANewerVersion() {
        let json = "{\"format\":\"yapper.history\",\"version\":99,\"exportedAt\":\"2027-01-15T08:00:00Z\",\"records\":[]}"
        XCTAssertThrowsError(try HistoryExport.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? HistoryExport.ImportError, .newerVersion(99))
        }
    }

    // MARK: Merge

    func testMergeAddsOnlyNewRecordsNewestFirst() {
        let a = record("a", hoursAgo: 1)
        let b = record("b", hoursAgo: 5)
        var edited = a
        edited.text = "a, changed elsewhere"
        let c = record("c", hoursAgo: 3)
        let (merged, added) = HistoryExport.merge([a, b], [edited, c, c])
        XCTAssertEqual(added.map(\.id), [c.id])
        XCTAssertEqual(merged.map(\.text), ["a", "c", "b"])
    }

    func testImportingTheSameExportTwiceAddsNothing() throws {
        let records = [record("one"), record("two", hoursAgo: 1)]
        let archive = try HistoryExport.decode(HistoryExport.json(records, now: now))
        let first = HistoryExport.merge([], archive.records)
        XCTAssertEqual(first.added.count, 2)
        let second = HistoryExport.merge(first.records, archive.records)
        XCTAssertTrue(second.added.isEmpty)
        XCTAssertEqual(second.records.map(\.id), first.records.map(\.id))
    }

    func testStatsMergeTakesTheLargerTotals() {
        let here = ["2027-01-14": DayTotals(words: 10, dictations: 1, seconds: 4),
                    "2027-01-15": DayTotals(words: 50, dictations: 5, seconds: 20)]
        let incoming = ["2027-01-15": DayTotals(words: 30, dictations: 6, seconds: 10),
                        "2027-01-16": DayTotals(words: 7, dictations: 1, seconds: 3)]
        let merged = DayTotals.merged(here, incoming)
        XCTAssertEqual(merged["2027-01-14"], here["2027-01-14"])
        XCTAssertEqual(merged["2027-01-15"], DayTotals(words: 50, dictations: 6, seconds: 20))
        XCTAssertEqual(merged["2027-01-16"], incoming["2027-01-16"])
        XCTAssertEqual(DayTotals.merged(merged, incoming), merged)
    }

    func testFileName() {
        XCTAssertEqual(HistoryExport.fileName(.csv, now: now, timeZone: utc), "Yapper history 2027-01-15.csv")
        XCTAssertEqual(HistoryExport.Format.allCases.map(\.fileExtension), ["txt", "md", "json", "csv"])
    }
}
