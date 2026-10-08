import XCTest

final class RetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ago(hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3_600)
    }

    func testForeverKeepsEverything() {
        XCTAssertFalse(Retention.isExpired(ago(hours: 100_000), hours: -1, now: now))
    }

    func testDontKeepDeletesEverything() {
        XCTAssertTrue(Retention.isExpired(now, hours: 0, now: now))
    }

    func testOneHour() {
        XCTAssertFalse(Retention.isExpired(ago(hours: 0.5), hours: 1, now: now))
        XCTAssertTrue(Retention.isExpired(ago(hours: 1.5), hours: 1, now: now))
    }

    func testThirtyDays() {
        XCTAssertFalse(Retention.isExpired(ago(hours: 29 * 24), hours: 30 * 24, now: now))
        XCTAssertTrue(Retention.isExpired(ago(hours: 31 * 24), hours: 30 * 24, now: now))
    }

    func testLabels() {
        XCTAssertEqual(Retention.recordingChoices.map(Retention.label(hours:)),
                       ["Don't keep", "1 hour", "1 day", "7 days", "30 days", "90 days", "Forever"])
        XCTAssertEqual(Retention.phrase(hours: 7 * 24), "for 7 days")
        XCTAssertEqual(Retention.phrase(hours: -1), "forever")
    }

    func testDefaultIsAChoice() {
        XCTAssertTrue(Retention.recordingChoices.contains(Retention.defaultRecordingHours))
    }
}
