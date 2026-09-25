import XCTest

/// Screenshots of the app's main screens. `-screenshots` skips onboarding.
final class AppScreenshots: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testMainScreens() {
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshots"] + (dark ? ["-dark"] : [])
            app.launch()
            let suffix = dark ? "dark" : "light"

            attach(app, name: "home-\(suffix)")

            app.buttons["How it works"].firstMatch.tap()
            attach(app, name: "home-how-it-works-\(suffix)")

            let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
            if field.waitForExistence(timeout: 2) {
                app.swipeUp()
                field.tap()
                Thread.sleep(forTimeInterval: 1)
                attach(app, name: "home-try-it-keyboard-\(suffix)")
                if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            }

            app.tabBars.buttons["History"].tap()
            attach(app, name: "history-\(suffix)")
            app.cells.element(boundBy: 1).tap()
            attach(app, name: "history-failed-detail-\(suffix)")
            app.swipeDown(velocity: .fast)
            let more = app.buttons["More"].firstMatch
            if more.waitForExistence(timeout: 2) {
                more.tap()
                if app.buttons["Delete All"].waitForExistence(timeout: 2) {
                    app.buttons["Delete All"].tap()
                    attach(app, name: "history-delete-all-1-\(suffix)")
                    app.alerts.buttons["Cancel"].firstMatch.tap()
                }
            }

            app.tabBars.buttons["Settings"].tap()
            attach(app, name: "settings-1-\(suffix)")
            app.swipeUp()
            attach(app, name: "settings-2-\(suffix)")
            app.swipeUp()
            attach(app, name: "settings-3-\(suffix)")

            app.tabBars.buttons["Home"].tap()
            app.swipeDown()
            let models = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Parakeet'")).firstMatch
            if models.waitForExistence(timeout: 2) {
                models.tap()
                attach(app, name: "models-\(suffix)")
            }
            app.terminate()
        }
    }

    /// Every onboarding step, light and dark.
    func testOnboarding() {
        for dark in [false, true] {
            for (index, step) in ["welcome", "microphone", "model", "keyboard", "fullAccess", "tryIt"].enumerated() {
                let app = XCUIApplication()
                app.launchArguments = ["-onboarding", "-onboardingStep", step] + (dark ? ["-dark"] : [])
                app.launch()
                attach(app, name: "onboarding-\(index + 1)-\(step)-\(dark ? "dark" : "light")")
                app.terminate()
            }
        }
    }

    /// Turns the engine on, goes to the Home Screen and captures the Dynamic
    /// Island. Needs the simulator to have an audio input.
    func testDynamicIsland() {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshots"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        app.switches.firstMatch.tap()
        for label in ["Allow", "OK"] where springboard.alerts.buttons[label].waitForExistence(timeout: 3) {
            springboard.alerts.buttons[label].tap()
        }
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "island-0-app-engine-on")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "island-1-compact"
        shot.lifetime = .keepAlways
        add(shot)

        // Long-press the island to expand it.
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03))
        top.press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1)
        let expanded = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expanded.name = "island-2-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)

        // Collapse it again and give the compact view time to draw.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        Thread.sleep(forTimeInterval: 5)
        let compact = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compact.name = "island-3-compact-settled"
        compact.lifetime = .keepAlways
        add(compact)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
