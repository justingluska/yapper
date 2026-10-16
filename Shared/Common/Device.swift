import Foundation

/// Words for the device Yapper runs on, so shared messages read right on
/// both the iPhone and the Mac.
enum Device {
    #if os(macOS)
    static let name = "Mac"
    static let os = "macOS"
    static let systemSettings = "System Settings"
    #else
    static let name = "iPhone"
    static let os = "iOS"
    static let systemSettings = "iOS Settings"
    #endif
}
