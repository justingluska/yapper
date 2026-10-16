import AppKit
import SwiftUI

/// Yapper for Mac: lives in the menu bar. Hold the dictation key (fn by
/// default) in any app, talk, let go, and the words are typed where the
/// cursor is. Transcribed on this Mac; nothing leaves it.
@main
struct YapperMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var dictation = MacDictation.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(dictation)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        switch dictation.phase {
        case .idle: return dictation.isSetUp ? "waveform" : "waveform.badge.exclamationmark"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let dictation = MacDictation.shared
        dictation.openMainWindow = { MainWindowController.shared.show() }
        dictation.launch()
        // First run, or a permission was taken away: show the setup steps.
        if !Settings.onboarded || !dictation.isSetUp {
            MainWindowController.shared.show(.setup)
        }
    }

    /// Opening Yapper again from Finder or Spotlight shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }
}
