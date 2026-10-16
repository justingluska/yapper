import Foundation

/// Turns presses of the dictation key into start, finish and cancel.
///
/// - Hold the key and talk; let go to finish (push-to-talk).
/// - Tap it instead and Yapper keeps listening hands-free until the next tap.
/// - Another key pressed right after the dictation key means it was part of
///   a shortcut (fn-F, Option-E), not a dictation: that one is cancelled.
///
/// Pure state, no timers or events, so it's tested on its own.
struct TalkGesture {
    enum Action: Equatable {
        case none
        case start
        case finish
        case cancel
    }

    enum State: Equatable {
        case idle
        /// Key down since the given time, recording.
        case holding(since: TimeInterval)
        /// Key released after a tap: recording until the next press.
        case handsFree
        /// The press that ended hands-free; waiting for its release.
        case stopping
    }

    /// Shorter than this is a tap, longer is a hold.
    var tapLimit: TimeInterval = 0.3

    private(set) var state: State = .idle

    var isRecording: Bool {
        switch state {
        case .holding, .handsFree: return true
        case .idle, .stopping: return false
        }
    }

    mutating func press(at time: TimeInterval) -> Action {
        switch state {
        case .idle:
            state = .holding(since: time)
            return .start
        case .handsFree:
            state = .stopping
            return .finish
        case .holding, .stopping:
            return .none
        }
    }

    mutating func release(at time: TimeInterval) -> Action {
        switch state {
        case let .holding(since):
            if time - since < tapLimit {
                state = .handsFree
                return .none
            }
            state = .idle
            return .finish
        case .stopping:
            state = .idle
            return .none
        case .idle, .handsFree:
            return .none
        }
    }

    /// Another key went down.
    mutating func otherKey(at time: TimeInterval) -> Action {
        guard case let .holding(since) = state, time - since < tapLimit else { return .none }
        state = .idle
        return .cancel
    }

    /// Forget everything: the dictation ended some other way (Escape, an
    /// error, the app refused to start).
    mutating func reset() {
        state = .idle
    }
}
