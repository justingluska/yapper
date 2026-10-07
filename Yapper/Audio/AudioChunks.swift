import Foundation

/// Splits a long recording into pieces for Apple's older recognizer, which
/// Apple documents as stopping after one minute of audio. Pieces are about
/// the same length, so there's never a sliver of silence at the end, and each
/// cut falls at the quietest moment near its spot, so no word is split.
enum AudioChunks {
    /// Ranges covering all of `samples`, in order. Each is at most
    /// `target + 2 * slack` seconds long; a recording no longer than
    /// `target` stays whole.
    static func split(_ samples: [Float], sampleRate: Double,
                      target: Double = 45, slack: Double = 5) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }
        let targetLength = Int(target * sampleRate)
        guard targetLength > 0, samples.count > targetLength else { return [0..<samples.count] }

        let pieces = (samples.count + targetLength - 1) / targetLength
        let spacing = Double(samples.count) / Double(pieces)
        let reach = Int(slack * sampleRate)
        let window = max(1, Int(0.1 * sampleRate))

        var ranges: [Range<Int>] = []
        var start = 0
        for index in 1..<pieces {
            let ideal = Int(Double(index) * spacing)
            let low = max(start + window, ideal - reach)
            let high = min(samples.count - window, ideal + reach)
            let cut = high > low ? quietest(samples, from: low, to: high, window: window) : ideal
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<samples.count)
        return ranges
    }

    /// The middle of the quietest `window`-long stretch between `from` and
    /// `to`, stepping half a window at a time.
    private static func quietest(_ samples: [Float], from: Int, to: Int, window: Int) -> Int {
        var best = (from + to) / 2
        var bestEnergy = Float.infinity
        var position = from
        while position + window <= to {
            var energy: Float = 0
            for i in position..<(position + window) { energy += samples[i] * samples[i] }
            if energy < bestEnergy {
                bestEnergy = energy
                best = position + window / 2
            }
            position += max(1, window / 2)
        }
        return best
    }
}
