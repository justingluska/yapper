import AppKit

/// The key held to dictate. Modifier keys only: they type nothing on their
/// own, so holding one never leaves stray characters in the app you're in.
enum TriggerKey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fn: return "fn (Globe)"
        case .rightOption: return "Right Option ⌥"
        case .rightCommand: return "Right Command ⌘"
        }
    }

    /// Short name for sentences: "Hold fn to dictate".
    var shortName: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "right ⌥"
        case .rightCommand: return "right ⌘"
        }
    }

    /// The key's virtual key code (kVK_Function, kVK_RightOption, kVK_RightCommand).
    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        }
    }

    /// Whether the key is down, from a flagsChanged event's modifier flags.
    /// The right-hand keys are read from the device-specific bits, so holding
    /// the left key at the same time doesn't hide a release of the right one.
    func isDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .fn: return flags.contains(.function)
        case .rightOption: return flags.rawValue & Self.deviceRightOption != 0
        case .rightCommand: return flags.rawValue & Self.deviceRightCommand != 0
        }
    }

    /// NX_DEVICERALTKEYMASK and NX_DEVICERCMDKEYMASK from IOKit's IOLLEvent.h.
    static let deviceRightOption: UInt = 0x40
    static let deviceRightCommand: UInt = 0x10
}
