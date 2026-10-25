import Foundation
import QuartzCore

/// One microphone level, 0...1, and when it was heard (`LevelFeed.now` time).
struct LevelSample: Equatable {
    var time: Double
    var level: Float
}

/// The live microphone level, from the app's audio thread to whatever draws
/// it: the keyboard's bars and the app's own waveform.
///
/// iOS hands an input tap about 100 ms of audio at a time, so one level per
/// buffer can never look better than ten frames a second. The recorder splits
/// each buffer into 10 ms windows instead and writes every window's level here
/// with the time it was heard; `LevelMeter` plays them back a buffer late, at
/// the display's frame rate.
///
/// It's a small memory-mapped file in the App Group container, not
/// UserDefaults: a hundred writes a second through cfprefsd would cost IPC on
/// both sides and arrive in lumps. Here a write is one store and a read is a
/// copy of 512 bytes. Each slot is a single 64-bit word (time and level packed
/// together), so a reader in the other process never sees half a write and
/// neither side needs a lock. A slot left over from an earlier recording just
/// carries an old time, and readers skip it.
final class LevelFeed {
    static let capacity = 64

    /// The clock both processes stamp and read with: seconds since boot, the
    /// same in every process (AVAudioTime's host time converts to it).
    static var now: Double { CACurrentMediaTime() }

    private let slots: UnsafeMutablePointer<UInt64>
    private let mapped: Bool
    /// Only the writer (one audio thread) touches this.
    private var next = 0

    /// A feed in this process's memory only, for previews and tests.
    init() {
        slots = .allocate(capacity: Self.capacity)
        slots.initialize(repeating: 0, count: Self.capacity)
        mapped = false
    }

    /// The feed shared through `url`, created if it isn't there yet. Nil when
    /// the file can't be opened (the keyboard without Full Access).
    init?(url: URL) {
        let size = Self.capacity * MemoryLayout<UInt64>.stride
        let fd = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return nil }
        if info.st_size < size, ftruncate(fd, off_t(size)) != 0 { return nil }
        let memory = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard let memory, memory != MAP_FAILED else { return nil }
        slots = memory.bindMemory(to: UInt64.self, capacity: Self.capacity)
        mapped = true
    }

    deinit {
        if mapped {
            munmap(slots, Self.capacity * MemoryLayout<UInt64>.stride)
        } else {
            slots.deallocate()
        }
    }

    /// Writes one level. Call from a single thread (the audio thread).
    func write(_ level: Float, at time: Double) {
        slots[next] = Self.pack(LevelSample(time: time, level: level))
        next = (next + 1) % Self.capacity
    }

    /// The levels heard after `since`, oldest first. Fills `samples`, keeping
    /// its storage, so a reader calling this every frame doesn't allocate.
    func read(since: Double, into samples: inout [LevelSample]) {
        samples.removeAll(keepingCapacity: true)
        for index in 0..<Self.capacity {
            if let sample = Self.unpack(slots[index]), sample.time > since {
                samples.append(sample)
            }
        }
        samples.sort { $0.time < $1.time }
    }

    // MARK: Packing

    /// Time in microseconds in the top 48 bits (nine years of uptime), the
    /// level in the bottom 16. Zero is an empty slot.
    static func pack(_ sample: LevelSample) -> UInt64 {
        let micros = UInt64(max(0, min(sample.time * 1_000_000, Double((1 << 48) - 1))))
        let level = UInt64((max(0, min(sample.level, 1)) * 65_535).rounded())
        return micros << 16 | level
    }

    static func unpack(_ word: UInt64) -> LevelSample? {
        guard word != 0 else { return nil }
        return LevelSample(time: Double(word >> 16) / 1_000_000, level: Float(word & 0xFFFF) / 65_535)
    }
}
