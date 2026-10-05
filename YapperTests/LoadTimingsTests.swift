import XCTest

final class LoadTimingsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testDurationsFromStepStarts() throws {
        let starts: [Int: Date] = [0: start, 1: start + 1, 2: start + 2, 3: start + 12, 4: start + 13, 5: start + 14]
        let timings = try XCTUnwrap(LoadTimings(stepStarts: starts, finished: start + 16, stepCount: 6))
        XCTAssertEqual(timings.steps, [1, 1, 10, 1, 1, 2])
        XCTAssertEqual(timings.total, 16)
    }

    func testMissingStepTakesNoTime() throws {
        let starts: [Int: Date] = [0: start, 2: start + 3, 3: start + 5, 4: start + 6, 5: start + 7]
        let timings = try XCTUnwrap(LoadTimings(stepStarts: starts, finished: start + 8, stepCount: 6))
        XCTAssertEqual(timings.steps, [3, 0, 2, 1, 1, 1])
    }

    func testNoStartNoTimings() {
        XCTAssertNil(LoadTimings(stepStarts: [2: start], finished: start + 1, stepCount: 6))
    }

    func testProgressMidStep() {
        let timings = LoadTimings(steps: [1, 1, 10, 1, 1, 2])
        let (fraction, remaining) = timings.progress(step: 2, inStep: 5)
        XCTAssertEqual(fraction, 7.0 / 16, accuracy: 0.0001)
        XCTAssertEqual(remaining, 9, accuracy: 0.0001)
    }

    func testOverrunHoldsShortOfStepEnd() {
        let timings = LoadTimings(steps: [1, 1, 10, 1, 1, 2])
        let (fraction, remaining) = timings.progress(step: 2, inStep: 30)
        XCTAssertEqual(fraction, 11.5 / 16, accuracy: 0.0001)
        XCTAssertEqual(remaining, 4, accuracy: 0.0001)
    }

    func testNeverReportsDone() {
        let timings = LoadTimings(steps: [0, 0, 0, 0, 0, 1])
        XCTAssertLessThan(timings.progress(step: 5, inStep: 100).fraction, 1)
    }
}
