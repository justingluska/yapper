import SwiftUI

/// Settings › Siri, Action Button and Control Center: the ways to start
/// Yapper without the keyboard, and where to set each one up.
struct ShortcutsHelpView: View {
    private static let actions: [(String, String)] = [
        ("Yap Hands-Free",
         "For the car, or a quick note. Listens without opening Yapper or unlocking your iPhone, stops when you stop talking, and saves your words to History and the clipboard. Say it or tap it again, or tap Done on the Lock Screen, to finish early."),
        ("Turn On Yapper",
         "Turns the speech engine on without leaving your app, so the Yapper keyboard's mic types straight into the field you're in."),
        ("Start Dictating",
         "Opens Yapper and listens there. Your words are copied when you tap Done."),
    ]

    private static let places: [(String, String)] = [
        ("Siri",
         "Say \"Hey Siri, yap with Yapper\" for Yap Hands-Free, or \"Turn on Yapper\". Works with CarPlay too. No setup needed."),
        ("Control Center",
         "Swipe down from the top right, tap + › Add a Control, and search for Yapper."),
        ("Lock Screen",
         "Long-press the Lock Screen › Customize › Lock Screen, then swap a button at the bottom for a Yapper control."),
        ("Action Button",
         "Settings › Action Button › Controls, then pick a Yapper control."),
        ("Back Tap",
         "Settings › Accessibility › Touch › Back Tap, then pick a Yapper shortcut."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(title: "Siri and controls", subtitle: "Start Yapper without the keyboard.")
                list(Self.actions)
                Text("Where to put them")
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 8)
                list(Self.places)
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func list(_ points: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.0)
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(Theme.textEmphasis)
                    Text(point.1)
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
