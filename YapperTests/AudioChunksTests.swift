import XCTest

final class AudioChunksTests: XCTestCase {
    /// 100 samples a second keeps the arrays small; the maths is the same.
    private let rate = 100.0

    private func noise(seconds: Double) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(($0 * 7919) % 200) / 100 - 1 }
    }

    private func assertCovers(_ ranges: [Range<Int>], count: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ranges.first?.lowerBound, 0, file: file, line: line)
        XCTAssertEqual(ranges.last?.upperBound, count, file: file, line: line)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(a.upperBound, b.lowerBound, file: file, line: line)
        }
    }

    func testEmptyRecordingHasNoPieces() {
        XCTAssertEqual(AudioChunks.split([], sampleRate: rate), [])
    }

    func testShortRecordingStaysWhole() {
        let samples = noise(seconds: 44)
        XCTAssertEqual(AudioChunks.split(samples, sampleRate: rate), [0..<samples.count])
    }

    func testLongRecordingPiecesStayUnderAppleLimit() {
        for seconds in [46.0, 59, 61, 95, 600] {
            let samples = noise(seconds: seconds)
            let ranges = AudioChunks.split(samples, sampleRate: rate)
            XCTAssertGreaterThan(ranges.count, 1, "\(seconds) s")
            assertCovers(ranges, count: samples.count)
            for range in ranges {
                XCTAssertLessThanOrEqual(Double(range.count) / rate, 55, "\(seconds) s")
                // Even pieces: no sliver of a piece at the end.
                XCTAssertGreaterThan(Double(range.count) / rate, 10, "\(seconds) s")
            }
        }
    }

    func testCutFallsInThePause() {
        // 70 s of speech-like noise with a half-second pause at 33 s, close
        // to the even split at 35 s.
        var samples = noise(seconds: 70)
        let pause = Int(33 * rate)..<Int(33.5 * rate)
        for i in pause { samples[i] = 0 }
        let ranges = AudioChunks.split(samples, sampleRate: rate)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertTrue(pause.contains(ranges[0].upperBound), "cut at \(ranges[0].upperBound)")
        assertCovers(ranges, count: samples.count)
    }
}
