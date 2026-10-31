import XCTest

final class SilenceDetectorTests: XCTestCase {
    /// Feeds `seconds` of one level at 10 ms a step, from `time`. Returns the
    /// first event and the time after the last level fed.
    private func feed(_ detector: SilenceDetector, _ level: Float, for seconds: Double,
                      from time: Double) -> (event: SilenceDetector.Event?, time: Double) {
        var now = time
        let end = time + seconds
        while now < end {
            if let event = detector.feed(level, at: now) { return (event, now) }
            now += 0.01
        }
        return (nil, now)
    }

    private func armed() -> SilenceDetector {
        let detector = SilenceDetector()
        detector.arm()
        return detector
    }

    func testFinishesAfterSpeechThenAPause() {
        let detector = armed()
        var step = feed(detector, 0.1, for: 1, from: 0)
        step = feed(detector, 0.7, for: 3, from: step.time)
        XCTAssertNil(step.event)
        let spokeUntil = step.time
        step = feed(detector, 0.1, for: 5, from: step.time)
        XCTAssertEqual(step.event, .finished)
        XCTAssertEqual(step.time - spokeUntil, SilenceDetector.pause, accuracy: 0.05)
    }

    func testAShortPauseMidSentenceDoesNotFinish() {
        let detector = armed()
        var step = feed(detector, 0.1, for: 0.5, from: 0)
        step = feed(detector, 0.7, for: 2, from: step.time)
        step = feed(detector, 0.1, for: SilenceDetector.pause - 0.5, from: step.time)
        XCTAssertNil(step.event)
        step = feed(detector, 0.7, for: 2, from: step.time)
        XCTAssertNil(step.event)
    }

    func testGivesUpWhenNothingIsSaid() {
        let detector = armed()
        let step = feed(detector, 0.1, for: SilenceDetector.patience + 1, from: 0)
        XCTAssertEqual(step.event, .nothingHeard)
        XCTAssertEqual(step.time, SilenceDetector.patience, accuracy: 0.05)
    }

    func testASingleClickIsNotSpeech() {
        let detector = armed()
        var step = feed(detector, 0.1, for: 1, from: 0)
        step = feed(detector, 0.9, for: 0.05, from: step.time)
        step = feed(detector, 0.1, for: SilenceDetector.patience, from: step.time)
        XCTAssertEqual(step.event, .nothingHeard)
    }

    /// Road noise louder than a quiet room's speech threshold is background,
    /// and speech over it still counts.
    func testFollowsLoudBackgroundNoise() {
        let detector = armed()
        var step = feed(detector, 0.45, for: 3, from: 0)
        XCTAssertNil(step.event)
        step = feed(detector, 0.8, for: 2, from: step.time)
        XCTAssertNil(step.event)
        step = feed(detector, 0.45, for: 5, from: step.time)
        XCTAssertEqual(step.event, .finished)
    }

    func testSpeakingRightAwayStillCounts() {
        let detector = armed()
        var step = feed(detector, 0.7, for: 2, from: 0)
        step = feed(detector, 0.1, for: 5, from: step.time)
        XCTAssertEqual(step.event, .finished)
    }

    func testSilentWhenDisarmedAndAfterAnEvent() {
        let detector = SilenceDetector()
        XCTAssertNil(feed(detector, 0.1, for: 20, from: 0).event)
        detector.arm()
        XCTAssertEqual(feed(detector, 0.1, for: 20, from: 0).event, .nothingHeard)
        XCTAssertNil(feed(detector, 0.1, for: 20, from: 20).event)
    }
}
