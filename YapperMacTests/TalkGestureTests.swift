import AppKit
import XCTest

final class TalkGestureTests: XCTestCase {
    func testHoldIsPushToTalk() {
        var gesture = TalkGesture()
        XCTAssertEqual(gesture.press(at: 0), .start)
        XCTAssertTrue(gesture.isRecording)
        XCTAssertEqual(gesture.release(at: 2), .finish)
        XCTAssertEqual(gesture.state, .idle)
    }

    func testTapStartsHandsFreeAndNextTapFinishes() {
        var gesture = TalkGesture()
        XCTAssertEqual(gesture.press(at: 0), .start)
        XCTAssertEqual(gesture.release(at: 0.1), .none)
        XCTAssertEqual(gesture.state, .handsFree)
        XCTAssertTrue(gesture.isRecording)
        XCTAssertEqual(gesture.press(at: 5), .finish)
        XCTAssertFalse(gesture.isRecording)
        XCTAssertEqual(gesture.release(at: 5.1), .none)
        XCTAssertEqual(gesture.state, .idle)
    }

    func testHoldExactlyAtTheLimitCountsAsAHold() {
        var gesture = TalkGesture()
        _ = gesture.press(at: 1)
        XCTAssertEqual(gesture.release(at: 1.3), .finish)
    }

    func testShortcutRightAfterTheKeyCancels() {
        var gesture = TalkGesture()
        _ = gesture.press(at: 0)
        XCTAssertEqual(gesture.otherKey(at: 0.05), .cancel)
        XCTAssertEqual(gesture.state, .idle)
        // The release that follows does nothing.
        XCTAssertEqual(gesture.release(at: 0.2), .none)
    }

    func testOtherKeysLaterInALongHoldAreIgnored() {
        var gesture = TalkGesture()
        _ = gesture.press(at: 0)
        XCTAssertEqual(gesture.otherKey(at: 1), .none)
        XCTAssertEqual(gesture.release(at: 2), .finish)
    }

    func testOtherKeysDuringHandsFreeAreIgnored() {
        var gesture = TalkGesture()
        _ = gesture.press(at: 0)
        _ = gesture.release(at: 0.1)
        XCTAssertEqual(gesture.otherKey(at: 0.15), .none)
        XCTAssertEqual(gesture.state, .handsFree)
    }

    func testRepeatedPressWhileHoldingDoesNothing() {
        var gesture = TalkGesture()
        _ = gesture.press(at: 0)
        XCTAssertEqual(gesture.press(at: 0.5), .none)
    }

    func testResetForgetsHandsFree() {
        var gesture = TalkGesture()
        _ = gesture.press(at: 0)
        _ = gesture.release(at: 0.1)
        gesture.reset()
        XCTAssertEqual(gesture.press(at: 1), .start)
    }

    func testRightOptionReadsTheDeviceBit() {
        let leftOnly = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20)
        let right = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | TriggerKey.deviceRightOption)
        XCTAssertFalse(TriggerKey.rightOption.isDown(leftOnly))
        XCTAssertTrue(TriggerKey.rightOption.isDown(right))
    }

    func testFnReadsTheFunctionFlag() {
        XCTAssertTrue(TriggerKey.fn.isDown(.function))
        XCTAssertFalse(TriggerKey.fn.isDown([]))
    }
}
