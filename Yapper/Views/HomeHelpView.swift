import SwiftUI

/// Home's help: how Yapper works in four lines, and the way to the longer
/// pages in Settings.
struct HomeHelpView: View {
    /// Whether the Yapper keyboard still needs adding; offers the setup.
    let needsKeyboard: Bool
    /// Opens the keyboard setup (Home shows it once this sheet is gone).
    let onSetup: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageTitle(title: "How Yapper works")
                    VStack(alignment: .leading, spacing: 16) {
                        NumberedStep(number: 1, text: "Turn Yapper on with the power button. The mic stays ready for \(Settings.sessionLabel).")
                        NumberedStep(number: 2, text: "In any app, switch to the Yapper keyboard with \(Image(systemName: "globe")) and tap the mic to talk. Tap again to finish.")
                        NumberedStep(number: 3, text: Settings.returnToApp
                            ? "The first time, Yapper opens to start listening, then takes you back. If it can't, swipe right along the bottom edge."
                            : "The first time, Yapper opens to start listening. Swipe right along the bottom edge to go back.")
                        NumberedStep(number: 4, text: "Or dictate here: **Dictate** at the top copies what you say.")
                    }
                    VStack(spacing: 0) {
                        if needsKeyboard {
                            row("Add the Yapper keyboard") {
                                dismiss()
                                onSetup()
                            }
                            Hairline()
                        }
                        link("How the speech engine works") { HowItWorksPage() }
                        Hairline()
                        link("Good to know") { GoodToKnowView() }
                        Hairline()
                        link("Try the keyboard") { TryKeyboardView() }
                    }
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func link<Destination: View>(_ title: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) { label(title) }
            .buttonStyle(.plain)
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title) }
            .buttonStyle(.plain)
    }

    private func label(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(16))
                .foregroundStyle(Theme.textEmphasis)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
