import AppKit

/// Watches the keyboard for the dictation key, in every app. macOS only
/// delivers other apps' key events to an app the user has allowed under
/// Privacy & Security › Accessibility, which Yapper needs anyway to paste.
/// Events are only looked at, never changed or swallowed.
@MainActor
final class HotkeyMonitor {
    var onPress: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?
    var onOtherKey: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?

    private var monitors: [Any] = []
    private var isDown = false

    /// Installs the monitors, replacing any from before. Call again once
    /// Accessibility is granted: monitors made before that never hear anything.
    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        // Global monitors miss events sent to Yapper's own windows.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        isDown = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let trigger = MacSettings.trigger
            guard event.keyCode == trigger.keyCode else { return }
            let down = trigger.isDown(event.modifierFlags)
            guard down != isDown else { return }
            isDown = down
            down ? onPress?() : onRelease?()
        case .keyDown:
            if event.keyCode == 53 { // kVK_Escape
                onEscape?()
            } else if !event.isARepeat {
                onOtherKey?()
            }
        default:
            break
        }
    }
}
