import Foundation

/// Decides when a hands-free dictation is over: once the speaker has said
/// something and then gone quiet for a moment. Fed the recorder's levels
/// (0...1 for -50...0 dBFS, one per 10 ms). "Quiet" is relative to the room,
/// not a fixed loudness: road noise in a car sits well above a quiet office,
/// so the detector follows the background level and listens for speech
/// standing out from it.
final class SilenceDetector {
    enum Event: Equatable {
        /// Speech, then `pause` seconds without it.
        case finished
        /// Nothing that sounded like speech within `patience` seconds (and
        /// nothing just now that might be the start of it).
        case nothingHeard
    }

    /// How long a pause ends the dictation. Long enough to think mid-sentence.
    static let pause: Double = 2.5
    /// How long to wait for the first word.
    static let patience: Double = 10

    /// Speech stands this far above the background: 0.16 is 8 dB.
    private static let margin: Float = 0.16
    /// And is at least this loud (-38 dBFS), so a silent room isn't speech.
    private static let minimumSpeech: Float = 0.24
    /// This much speech in total before a pause counts, so a cough or a door
    /// doesn't end the dictation before it starts.
    private static let speechNeeded: Double = 0.25

    private let lock = NSLock()
    private var armed = false
    private var started: Double?
    private var floor: Float = 0
    private var speech: Double = 0
    private var lastSpeech: Double?
    private var lastTime: Double?

    /// Starts listening for the end of a new dictation.
    func arm() {
        lock.withLock {
            armed = true
            started = nil
            speech = 0
            lastSpeech = nil
            lastTime = nil
        }
    }

    func disarm() {
        lock.withLock { armed = false }
    }

    /// Takes one level heard at `time` (seconds). Returns an event once, then
    /// stays quiet until armed again. Called on the audio thread.
    func feed(_ level: Float, at time: Double) -> Event? {
        lock.withLock {
            guard armed else { return nil }
            guard let started else {
                self.started = time
                // Capped, in case the first sound is already speech.
                floor = min(level, 0.3)
                lastTime = time
                return nil
            }
            let step = max(0, min(0.1, time - (lastTime ?? time)))
            lastTime = time

            if level > max(floor + Self.margin, Self.minimumSpeech) {
                speech += step
                lastSpeech = time
            }
            // The background level drops quickly to a quieter moment and
            // creeps up slowly, so speech itself barely moves it.
            floor += (level - floor) * (level < floor ? 0.2 : 0.002)

            if speech >= Self.speechNeeded, let lastSpeech, time - lastSpeech >= Self.pause {
                armed = false
                return .finished
            }
            if speech < Self.speechNeeded, time - started >= Self.patience,
               lastSpeech.map({ time - $0 >= Self.pause }) ?? true {
                armed = false
                return .nothingHeard
            }
            return nil
        }
    }
}
