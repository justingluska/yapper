import XCTest

/// Screenshots of the keyboard layout in every state, light and dark, for
/// reviewing design changes without a phone. Run by the Screenshots GitHub
/// workflow; the PNGs are uploaded as a build artifact.
final class KeyboardScreenshots: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testKeyboardStates() {
        for dark in [false, true] {
            for state in ["idle", "ready", "recording", "transcribing", "undo", "error", "typing"] {
                let app = XCUIApplication()
                app.launchArguments = ["-state", state] + (dark ? ["-dark"] : [])
                app.launch()
                // Let the level bars fill in.
                Thread.sleep(forTimeInterval: state == "recording" ? 1.5 : 0.6)
                attach(app, name: "keyboard-\(state)-\(dark ? "dark" : "light")")
                app.terminate()
            }
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
