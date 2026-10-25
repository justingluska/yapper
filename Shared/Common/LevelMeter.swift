import Foundation

/// Turns the `LevelFeed` into what a waveform draws, once per display frame.
///
/// - **Playback.** Levels arrive in lumps, a buffer's worth at a time. The
///   meter draws the voice as it was a little over one buffer ago, reading
///   between the 10 ms levels, so there is always a level on either side of
///   the moment it draws and the motion never stalls between lumps. How far
///   behind it plays adapts to how late the levels actually arrive.
/// - **Envelope.** Fast attack, slower release, so syllables pop and pauses
///   settle instead of flickering. Time-based, so 60 and 120 Hz look the same.
/// - **Bars.** The level is kept on a grid, one point every `step` seconds.
///   Bar `i` is the level at exactly `now - i * step`, read between grid
///   points, so the wave scrolls continuously instead of jumping a bar at a
///   time, and no bar ever speeds up or stops at a grid point.
///
/// A class so a view can keep one in `@State` and update it from a
/// `TimelineView` without invalidating itself. Updating twice for the same
/// frame is a no-op, so several views can share one meter.
final class LevelMeter {
    let barCount: Int
    let step: Double

    /// The smoothed level now, 0...1.
    private(set) var level: Float = 0

    /// The level on the grid, one point every `step`, newest first;
    /// `history[0]` is at `lastPush`.
    private var history: [Float]
    private var lastPush: Double?
    private var lastFrame: Double?
    /// How far behind the newest level the meter plays.
    private var delay = 0.12
    /// Recent worst gap between now and the newest level heard.
    private var peakGap = 0.0
    private var samples: [LevelSample] = []

    static let attack = 0.03
    static let release = 0.11
    /// Older than this, the feed has stopped (the recording ended) and the
    /// meter falls to silence instead of holding the last level.
    static let stale = 0.5

    init(barCount: Int, step: Double = 0.06) {
        self.barCount = barCount
        self.step = step
        history = Array(repeating: 0, count: barCount)
        samples.reserveCapacity(LevelFeed.capacity)
    }

    /// Back to silence, for the next recording.
    func reset() {
        level = 0
        history = Array(repeating: 0, count: barCount)
        lastPush = nil
        lastFrame = nil
        delay = 0.12
        peakGap = 0
    }

    /// Advances to the frame `date` (a `TimelineView` context date) and
    /// returns the bars, newest first. With `still`, for Reduce Motion, the
    /// bars show the current level without scrolling.
    func bars(at date: Date, feed: LevelFeed?, still: Bool = false) -> [Float] {
        let now = LevelFeed.now + date.timeIntervalSinceNow
        if now != lastFrame {
            feed?.read(since: now - 1, into: &samples)
            if feed == nil { samples.removeAll(keepingCapacity: true) }
            advance(to: now, samples: samples)
        }
        return still ? stillBars() : bars(now: now)
    }

    /// One frame at `now` (`LevelFeed.now` time), with the levels heard
    /// recently, oldest first.
    func advance(to now: Double, samples: [LevelSample]) {
        if now == lastFrame { return }
        // A long gap (the first frame, or the timeline was paused) is not
        // motion to smooth over.
        let dt = lastFrame.map { min(max(now - $0, 0), 0.1) } ?? 0
        let previous = (time: lastFrame ?? now, level: level)
        lastFrame = now

        level = smoothed(toward: target(now: now, dt: dt, samples: samples), dt: dt)

        guard var pushed = lastPush, now - pushed < step * Double(barCount) else {
            lastPush = now
            history[0] = level
            return
        }
        while now - pushed >= step {
            pushed += step
            // The level at the grid point itself, between this frame and
            // the last, not this frame's: frames don't land on the grid.
            let span = now - previous.time
            let t = span > 0 ? Float((pushed - previous.time) / span) : 1
            history.removeLast()
            history.insert(previous.level + (level - previous.level) * min(max(t, 0), 1), at: 0)
        }
        lastPush = pushed
    }

    /// The bars at `now`, newest first: bar 0 is the live level, bar `i` the
    /// level at `now - i * step`, between grid points `i` and `i - 1`.
    func bars(now: Double) -> [Float] {
        let fraction = Float(lastPush.map { min(max((now - $0) / step, 0), 1) } ?? 0)
        var bars = [Float](repeating: 0, count: barCount)
        guard barCount > 0 else { return bars }
        bars[0] = level
        for index in 1..<barCount {
            let older = history[index], newer = history[index - 1]
            bars[index] = older + (newer - older) * fraction
        }
        return bars
    }

    /// The level as a still meter: tallest nearest the source, tapering off.
    func stillBars() -> [Float] {
        (0..<barCount).map { index in
            level * (1 - 0.5 * Float(index) / Float(max(barCount - 1, 1)))
        }
    }

    // MARK: Playback

    private func target(now: Double, dt: Double, samples: [LevelSample]) -> Float {
        guard let newest = samples.last else { return 0 }
        let gap = now - newest.time
        if gap > Self.stale { return 0 }

        // Play just behind the worst recent lateness. The peak falls slowly,
        // so one quick buffer doesn't pull playback into the next late one;
        // the delay follows it quickly up (or the meter would run dry) and
        // gently down.
        peakGap = max(gap, peakGap - dt * 0.1)
        let wanted = min(peakGap + 0.015, Self.stale)
        let tau = wanted > delay ? 0.08 : 1.0
        delay += (wanted - delay) * (dt > 0 ? 1 - exp(-dt / tau) : 0)

        return Self.level(at: now - delay, in: samples)
    }

    /// The level at `time`, read linearly between the two levels around it.
    /// Before the first it's the first; after the last, the last.
    static func level(at time: Double, in samples: [LevelSample]) -> Float {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if time <= first.time { return first.level }
        if time >= last.time { return last.level }
        // Few enough (a second of 10 ms levels at most) for a linear search
        // from the end, where the playback point always is.
        var index = samples.count - 1
        while index > 0, samples[index - 1].time > time { index -= 1 }
        let before = samples[index - 1], after = samples[index]
        let span = after.time - before.time
        guard span > 0 else { return after.level }
        let t = Float((time - before.time) / span)
        return before.level + (after.level - before.level) * t
    }

    private func smoothed(toward target: Float, dt: Double) -> Float {
        guard dt > 0 else { return level }
        let tau = target > level ? Self.attack : Self.release
        return level + (target - level) * Float(1 - exp(-dt / tau))
    }
}
