import Foundation

/// The way back into the app the keyboard was typing in, by bundle ID. A link
/// only belongs here if opening it brings the app back where the user was,
/// not to its home screen, a new compose sheet, or an action: a bare
/// `scheme://` is a deep link, and each app decides what it means (`termius://`
/// opens Termius's new-host form; `claude://` may start a new chat). So only
/// links someone has checked on a device go here. Every other app, Safari
/// included, gets the swipe-back screen.
///
/// From the Dictus and VivaDicta catalogues (MIT, github.com/getdictus/dictus-ios,
/// github.com/n0an/VivaDicta), keeping the entries their audits checked.
/// To add one: leave the app mid-draft, open the link from Safari, and see
/// where it lands.
enum ReturnLinks {
    static let byBundleID: [String: String] = [
        // Checked on a device.
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.MobileSMS": "ichat://",
        "com.apple.mobilemail": "message://",
        "net.whatsapp.WhatsApp": "whatsapp-consumer://",
        "com.tinyspeck.chatlyio": "slack://open",
        "com.github.stormbreaker.prod": "github://",
        "com.openai.chat": "com.openai.chat://",
        "com.t3tools.t3code": "t3code://",
        // Checked in the simulator.
        "com.apple.reminders": "x-apple-reminderkit://",
        // Read in the app's source: a bare link matches no route and only
        // brings the app to the front.
        "com.telegram.telegram-ios": "tg://",
        "ph.telegra.Telegraph": "tg://",
        "org.whispersystems.signal": "sgnl://",
    ]

    static func url(for bundleID: String) -> URL? {
        byBundleID[bundleID].flatMap(URL.init(string:))
    }
}
