import Foundation

/// How long each step of loading a model took last time, so the next load can
/// show a moving bar and the time left. Core ML loads each part of the model
/// in one call with no progress of its own, so measuring a previous load is
/// the only honest estimate there is.
///
/// Steps match `Transcriber.LoadStage`: 0 is starting, 1–4 the four model
/// parts, 5 the warm-up.
struct LoadTimings: Codable, Equatable {
    /// Seconds spent in each step, indexed by step.
    var steps: [Double]

    var total: Double { steps.reduce(0, +) }

    /// Durations from the moments each step began and the moment loading
    /// finished. Steps that were never reported (FluidAudio skips none today,
    /// but a stage can arrive late) count as taking no time.
    init?(stepStarts: [Int: Date], finished: Date, stepCount: Int) {
        guard stepStarts[0] != nil else { return nil }
        steps = (0..<stepCount).map { step in
            guard let start = stepStarts[step] else { return 0 }
            let end = (step + 1..<stepCount).lazy.compactMap { stepStarts[$0] }.first ?? finished
            return max(end.timeIntervalSince(start), 0)
        }
    }

    init(steps: [Double]) {
        self.steps = steps
    }

    /// Fraction done (0..<1) and seconds left, given the step in progress and
    /// how long it has been running. A step that runs over its last time
    /// holds just short of its end rather than running past it, and its
    /// remaining time counts as zero.
    func progress(step: Int, inStep: TimeInterval) -> (fraction: Double, remaining: TimeInterval) {
        guard total > 0, steps.indices.contains(step) else { return (0, 0) }
        let before = steps[..<step].reduce(0, +)
        let expected = steps[step]
        let after = steps[(step + 1)...].reduce(0, +)
        let within = min(max(inStep, 0), expected * 0.95)
        let fraction = min((before + within) / total, 0.99)
        let remaining = max(expected - inStep, 0) + after
        return (fraction, remaining)
    }
}
