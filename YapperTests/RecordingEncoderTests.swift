import AVFoundation
import XCTest

final class RecordingEncoderTests: XCTestCase {
    /// Every rate an iPhone microphone records at: the built-in mic (48 and
    /// 44.1 kHz) and Bluetooth headsets (16 kHz wideband, 8 kHz narrowband).
    func testEveryMicrophoneRateIsSaved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for rate in [8_000.0, 16_000, 22_050, 24_000, 44_100, 48_000] {
            let samples = (0..<Int(rate)).map { Float(sin(Double($0) * 2 * .pi * 440 / rate)) * 0.3 }
            let url = dir.appendingPathComponent("\(Int(rate)).m4a")
            XCTAssertNoThrow(try RecordingEncoder.write(samples, sampleRate: rate, to: url), "\(Int(rate)) Hz")
            let file = try? AVAudioFile(forReading: url)
            XCTAssertNotNil(file, "\(Int(rate)) Hz wasn't readable")
            if let file { XCTAssertGreaterThan(file.length, 0, "\(Int(rate)) Hz") }
        }
    }
}
