import XCTest

/// Screenshots of the app's main screens. `-screenshots` skips onboarding.
final class AppScreenshots: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testMainScreens() {
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"

            // Home's other states, pinned: the simulator has no model to load
            // and no call to pause for.
            for state in ["on", "loading", "paused"] {
                let pinned = XCUIApplication()
                pinned.launchArguments = ["-screenshots", "-homeState", state] + (dark ? ["-dark"] : [])
                pinned.launch()
                attach(pinned, name: "home-\(state)-\(suffix)")
                pinned.terminate()
            }

            let app = XCUIApplication()
            app.launchArguments = ["-screenshots"] + (dark ? ["-dark"] : [])
            app.launch()

            attach(app, name: "home-off-\(suffix)")

            let setup = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Finish setup'")).firstMatch
            if setup.waitForExistence(timeout: 2) {
                setup.tap()
                Thread.sleep(forTimeInterval: 0.5)
                attach(app, name: "home-setup-\(suffix)")
                app.swipeDown(velocity: .fast)
                Thread.sleep(forTimeInterval: 0.5)
            }

            app.tabBars.buttons["History"].tap()
            attach(app, name: "history-\(suffix)")
            app.cells.element(boundBy: 1).tap()
            attach(app, name: "history-detail-\(suffix)")
            app.navigationBars.buttons["Done"].firstMatch.tap()

            app.tabBars.buttons["Settings"].tap()
            attach(app, name: "settings-1-\(suffix)")
            app.swipeUp()
            attach(app, name: "settings-2-\(suffix)")
            app.swipeUp()
            attach(app, name: "settings-3-\(suffix)")

            let tryKeyboard = app.buttons["Try the keyboard"].firstMatch
            scroll(app, to: tryKeyboard)
            if tryKeyboard.exists {
                tryKeyboard.tap()
                let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
                if field.waitForExistence(timeout: 2) {
                    field.tap()
                    Thread.sleep(forTimeInterval: 1)
                }
                attach(app, name: "settings-try-keyboard-\(suffix)")
            }
            app.terminate()
        }
    }

    /// History's tools with a fuller sample (`-sampleHistory`: older and
    /// longer dictations, some with recordings): a long dictation at full
    /// height, row swipes, Select mode, export options, and Settings ›
    /// History with both delete confirmations. Nothing is deleted: every
    /// confirmation is cancelled.
    func testHistoryManagement() {
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            var app = launch(dark: dark)

            app.tabBars.buttons["History"].tap()
            attach(app, name: "manage-01-history-\(suffix)")

            // A long dictation opens at full height and reads to the end.
            let long = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Okay, so here'")).firstMatch
            if long.waitForExistence(timeout: 2) {
                long.tap()
                attach(app, name: "manage-02-detail-long-\(suffix)")
                app.swipeUp()
                attach(app, name: "manage-03-detail-long-end-\(suffix)")
                app.navigationBars.buttons["Done"].firstMatch.tap()
            }

            // Row swipes: Delete and Share one way, Copy the other. Short
            // drags, so a full swipe never deletes.
            let row = app.cells.element(boundBy: 1)
            drag(row, from: 0.92, to: 0.5)
            attach(app, name: "manage-04-swipe-share-delete-\(suffix)")
            drag(row, from: 0.3, to: 0.95)
            drag(row, from: 0.08, to: 0.45)
            attach(app, name: "manage-05-swipe-copy-\(suffix)")
            drag(row, from: 0.7, to: 0.05)

            // Select mode.
            app.navigationBars.buttons["Select"].firstMatch.tap()
            attach(app, name: "manage-06-select-\(suffix)")
            app.cells.element(boundBy: 0).tap()
            app.cells.element(boundBy: 2).tap()
            attach(app, name: "manage-07-select-two-\(suffix)")
            app.buttons["history.selection.delete"].firstMatch.tap()
            attach(app, name: "manage-08-select-delete-confirm-\(suffix)")
            app.alerts.buttons["Cancel"].firstMatch.tap()
            app.navigationBars.buttons["Select All"].firstMatch.tap()
            attach(app, name: "manage-09-select-all-\(suffix)")
            app.buttons["history.selection.share"].firstMatch.tap()
            attach(app, name: "manage-10-export-selection-\(suffix)")
            app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'JSON'")).firstMatch.tap()
            let include = app.switches["Include recordings"].firstMatch
            if include.waitForExistence(timeout: 2) {
                // The tappable part of a SwiftUI toggle is its switch.
                let knob = include.switches.firstMatch
                (knob.exists ? knob : include).tap()
            }
            attach(app, name: "manage-11-export-json-recordings-\(suffix)")
            app.navigationBars.buttons["Cancel"].firstMatch.tap()
            app.navigationBars.buttons["Done"].firstMatch.tap()

            // Settings › History.
            app.tabBars.buttons["Settings"].tap()
            let deleteHistory = app.buttons["Delete all history…"].firstMatch
            scroll(app, to: deleteHistory)
            attach(app, name: "manage-12-settings-history-\(suffix)")

            app.buttons["Export history…"].firstMatch.tap()
            attach(app, name: "manage-13-settings-export-\(suffix)")
            app.navigationBars.buttons["Cancel"].firstMatch.tap()

            app.buttons["Delete all recordings…"].firstMatch.tap()
            attach(app, name: "manage-14-delete-recordings-first-\(suffix)")
            let recordingsNext = app.buttons["Delete All Recordings…"].firstMatch
            if recordingsNext.waitForExistence(timeout: 2) {
                recordingsNext.tap()
                attach(app, name: "manage-15-delete-recordings-final-\(suffix)")
                app.alerts.buttons["Cancel"].firstMatch.tap()
            }

            deleteHistory.tap()
            attach(app, name: "manage-16-delete-history-first-\(suffix)")
            let historyNext = app.buttons["Delete All History…"].firstMatch
            if historyNext.waitForExistence(timeout: 2) {
                historyNext.tap()
                attach(app, name: "manage-17-delete-history-final-\(suffix)")
                app.alerts.buttons["Cancel"].firstMatch.tap()
            }

            // The share sheet and the file picker run outside the app, so
            // capture the whole screen and start fresh after each.
            app.tabBars.buttons["History"].tap()
            app.navigationBars.buttons["Select"].firstMatch.tap()
            app.navigationBars.buttons["Select All"].firstMatch.tap()
            app.buttons["history.selection.share"].firstMatch.tap()
            app.buttons["export.share"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 3)
            attachScreen(name: "manage-18-share-sheet-\(suffix)")
            app.terminate()

            app = launch(dark: dark)
            app.tabBars.buttons["Settings"].tap()
            let importRow = app.buttons["Import history…"].firstMatch
            scroll(app, to: importRow)
            importRow.tap()
            Thread.sleep(forTimeInterval: 3)
            attachScreen(name: "manage-19-import-picker-\(suffix)")
            app.terminate()
        }
    }

    private func launch(dark: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshots", "-sampleHistory"] + (dark ? ["-dark"] : [])
        app.launch()
        return app
    }

    /// A horizontal drag across `element`, from and to fractions of its width.
    private func drag(_ element: XCUIElement, from start: CGFloat, to end: CGFloat) {
        guard element.waitForExistence(timeout: 2) else { return }
        element.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: element.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func scroll(_ app: XCUIApplication, to element: XCUIElement) {
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    private func attachScreen(name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Home's help sheet, light and dark.
    func testHomeHelp() {
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshots", "-homeState", "on", "-keyboardAdded"] + (dark ? ["-dark"] : [])
            app.launch()
            attach(app, name: "home-on-setup-done-\(dark ? "dark" : "light")")
            app.buttons["home.help"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.5)
            attach(app, name: "home-help-\(dark ? "dark" : "light")")
            app.terminate()
        }
    }

    /// The App Store set, light and dark: Home on, its help, History,
    /// stats and Cleanup, with the keyboard set up. The keyboard and
    /// onboarding shots come from KeyboardScreenshots and testOnboarding.
    func testAppStore() {
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let app = XCUIApplication()
            app.launchArguments = ["-screenshots", "-sampleHistory", "-homeState", "on", "-keyboardAdded"] + (dark ? ["-dark"] : [])
            app.launch()
            attach(app, name: "appstore-home-on-\(suffix)")
            app.buttons["home.help"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.5)
            attach(app, name: "appstore-home-help-\(suffix)")
            app.navigationBars.buttons["Done"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.5)

            app.tabBars.buttons["History"].tap()
            attach(app, name: "appstore-history-\(suffix)")
            app.tabBars.buttons["Settings"].tap()
            attach(app, name: "appstore-stats-\(suffix)")
            let cleanup = app.switches["Remove stutters (\"I I think\")"].firstMatch
            scroll(app, to: cleanup)
            // Bring Cleanup up to the top third, with History under it.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: app.frame.midX, dy: cleanup.frame.minY))
            from.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: 300)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            attach(app, name: "appstore-settings-cleanup-\(suffix)")
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

        app.buttons["home.power"].firstMatch.tap()
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
