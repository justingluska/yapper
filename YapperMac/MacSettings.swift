import Foundation
import ServiceManagement

/// Settings only the Mac app has. The shared ones (cleanup, dictionary,
/// History and recordings, model) live in `Settings`.
enum MacSettings {
    private enum Key {
        static let trigger = "mac.trigger"
        static let sounds = "mac.sounds"
        static let keepOnClipboard = "mac.keepOnClipboard"
        static let inputDevice = "mac.inputDevice"
    }

    private static var defaults: UserDefaults { Bridge.defaults }

    static var trigger: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: Key.trigger) ?? "") ?? .fn }
        set { defaults.set(newValue.rawValue, forKey: Key.trigger) }
    }

    /// A soft sound when listening starts and stops.
    static var sounds: Bool {
        get { defaults.object(forKey: Key.sounds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.sounds) }
    }

    /// Leave each dictation on the clipboard instead of putting back what
    /// was there. Off by default: on a Mac the clipboard is busy.
    static var keepOnClipboard: Bool {
        get { defaults.bool(forKey: Key.keepOnClipboard) }
        set { defaults.set(newValue, forKey: Key.keepOnClipboard) }
    }

    /// The microphone's Core Audio UID; nil follows the system's input.
    static var inputDeviceUID: String? {
        get { defaults.string(forKey: Key.inputDevice) }
        set { defaults.set(newValue, forKey: Key.inputDevice) }
    }

    /// Open Yapper at login, through macOS's own Login Items.
    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Yapper: login item change failed: \(error.localizedDescription)")
            }
        }
    }

    /// What the fn (Globe) key does by itself, from System Settings ›
    /// Keyboard: 0 is "Do Nothing". Anything else (emoji picker, Apple's
    /// dictation, input sources) fires alongside Yapper when fn is the key.
    /// An unset value means the factory setting, which is never "Do Nothing".
    static var globeKeyIsFree: Bool {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int == 0
    }
}
