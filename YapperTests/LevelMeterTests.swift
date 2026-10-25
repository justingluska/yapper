import XCTest

final class LevelFeedTests: XCTestCase {
    func testPackingRoundTrips() throws {
        let sample = LevelSample(time: 123_456.789_012, level: 0.42)
        let unpacked = try XCTUnwrap(LevelFeed.unpack(LevelFeed.pack(sample)))
        XCTAssertEqual(unpacked.time, sample.time, accuracy: 0.000_001)
        XCTAssertEqual(unpacked.level, sample.level, accuracy: 1.0 / 65_535)
    }

    func testEmptySlotIsNothing() {
        XCTAssertNil(LevelFeed.unpack(0))
    }

    func testReadsRecentOldestFirstAcrossTheWrap() {
        let feed = LevelFeed()
        for index in 0..<100 {
            feed.write(Float(index) / 100, at: 10 + Double(index) * 0.01)
        }
        var samples: [LevelSample] = []
        feed.read(since: 0, into: &samples)
        XCTAssertEqual(samples.count, LevelFeed.capacity)
        XCTAssertEqual(samples.first?.time ?? 0, 10 + 36 * 0.01, accuracy: 0.000_01)
        XCTAssertEqual(samples.last?.time ?? 0, 10 + 99 * 0.01, accuracy: 0.000_01)
        XCTAssertEqual(samples.map(\.time), samples.map(\.time).sorted())

        feed.read(since: 10.9, into: &samples)
        XCTAssertEqual(samples.count, 9)
    }

    func testSharedFileIsSeenByAnotherMapping() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("level-feed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try XCTUnwrap(LevelFeed(url: url))
        let reader = try XCTUnwrap(LevelFeed(url: url))
        writer.write(0.5, at: 42)
        var samples: [LevelSample] = []
        reader.read(since: 0, into: &samples)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.level ?? 0, 0.5, accuracy: 0.001)
    }
}

final class LevelMeterTests: XCTestCase {
    private let frame = 1.0 / 120

    func testReadsBetweenLevels() {
        let samples = [LevelSample(time: 1, level: 0), LevelSample(time: 1.01, level: 1)]
        XCTAssertEqual(LevelMeter.level(at: 1.0025, in: samples), 0.25, accuracy: 0.0001)
        XCTAssertEqual(LevelMeter.level(at: 0.5, in: samples), 0)
        XCTAssertEqual(LevelMeter.level(at: 2, in: samples), 1)
    }

    /// The real shape of the problem: 10 ms levels of a voice that rises and
    /// falls, arriving in 100 ms lumps 20 ms after their buffer ends, drawn at
    /// 120 Hz. Every frame must move a little; none may jump or stand still.
    func testLumpyFeedDrawsEveryFrameSmoothly() {
        let meter = LevelMeter(barCount: 9)
        let voice: (Double) -> Float = { t in Float(0.5 + 0.4 * sin(t * 2 * .pi * 1.5)) }
        var heard: [LevelSample] = []
        var deltas: [Float] = []
        var still = 0
        var previous: Float?

        var now = 0.0
        while now < 3 {
            // Buffers cover [k·0.1, (k+1)·0.1) and arrive at (k+1)·0.1 + 0.02.
            let delivered = Int(((now - 0.02) / 0.1).rounded(.down))
            let windows = max(0, delivered * 10)
            while heard.count < windows {
                let time = Double(heard.count) * 0.01 + 0.005
                heard.append(LevelSample(time: time, level: voice(time)))
            }
            meter.advance(to: now, samples: heard.filter { $0.time > now - 1 })
            if now > 1 {
                let level = meter.level
                if let previous {
                    deltas.append(abs(level - previous))
                    if level == previous { still += 1 }
                }
                previous = level
            }
            now += frame
        }

        XCTAssertEqual(still, 0, "frames where the wave froze")
        // A 1.5 Hz swing of ±0.4 moves at most ~0.03 per 120 Hz frame.
        XCTAssertLessThan(deltas.max() ?? 1, 0.04)
    }

    func testAttacksFasterThanItReleases() {
        let up = LevelMeter(barCount: 1)
        let down = LevelMeter(barCount: 1)
        // Settle `down` at full level first.
        var now = 0.0
        while now < 1 {
            let loud = (0..<100).map { LevelSample(time: now - 0.3 + Double($0) * 0.003, level: 1) }
            down.advance(to: now, samples: loud)
            now += frame
        }
        let start = now
        while now < start + 0.05 {
            let loud = (0..<100).map { LevelSample(time: now - 0.3 + Double($0) * 0.003, level: 1) }
            let quiet = (0..<100).map { LevelSample(time: now - 0.3 + Double($0) * 0.003, level: 0) }
            up.advance(to: now, samples: loud)
            down.advance(to: now, samples: quiet)
            now += frame
        }
        XCTAssertGreaterThan(up.level, 1 - down.level)
    }

    func testFallsSilentWhenTheFeedStops() {
        let meter = LevelMeter(barCount: 3)
        let last = [LevelSample(time: 0.1, level: 0.8)]
        var now = 0.1
        while now < 2 {
            meter.advance(to: now, samples: last)
            now += frame
        }
        XCTAssertLessThan(meter.level, 0.01)
    }

    /// Each bar samples the wave at a fixed distance behind now, so as it
    /// scrolls no bar moves faster than the wave itself: no seams at the grid.
    /// A 2 Hz swing of ±0.4 moves at most ~0.042 per 120 Hz frame.
    func testBarsScrollWithoutJumping() {
        let meter = LevelMeter(barCount: 9, step: 0.06)
        let voice: (Double) -> Float = { t in Float(0.5 + 0.4 * sin(t * 2 * .pi * 2)) }
        var previous: [Float]?
        var worst: Float = 0
        var now = 0.0
        while now < 3 {
            let heard = stride(from: max(0, now - 1), to: now - 0.05, by: 0.01).map {
                LevelSample(time: $0, level: voice($0))
            }
            meter.advance(to: now, samples: heard)
            let bars = meter.bars(now: now)
            if now > 1.5, let previous {
                worst = max(worst, zip(bars, previous).map { abs($0 - $1) }.max() ?? 0)
            }
            previous = bars
            now += frame
        }
        XCTAssertLessThan(worst, 0.05)
    }

    func testStillBarsFollowTheLevelWithoutHistory() {
        let meter = LevelMeter(barCount: 5)
        let loud = (0..<50).map { LevelSample(time: Double($0) * 0.01, level: 1) }
        var now = 0.5
        while now < 1 {
            meter.advance(to: now, samples: loud)
            now += frame
        }
        let bars = meter.stillBars()
        XCTAssertEqual(bars.first ?? 0, meter.level, accuracy: 0.0001)
        XCTAssertEqual(bars, bars.sorted(by: >))
    }
}
