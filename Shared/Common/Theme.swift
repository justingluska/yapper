import SwiftUI
import UIKit

// Yapper's style: flat surfaces, hairline borders instead of gray fills, translucent black/white
// fills for interactive states, two radii (12 for controls, 24 for cards) and Inter.

enum Theme {
    // MARK: Colors (light / dark pairs)

    static let background = dynamic(light: 0xFDFDFD, dark: 0x0F0F0F)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x191919)

    /// Four text grays: emphasis, default, muted, faint.
    static let textEmphasis = dynamic(light: 0x191919, dark: 0xFFFFFF)
    static let text = dynamic(light: 0x333333, dark: 0xD1D5DB)
    static let textMuted = dynamic(light: 0x656565, dark: 0x9CA3AF)
    static let textFaint = dynamic(light: 0x989898, dark: 0x6B7280)

    /// Card outline and hairline divider.
    static let border = dynamic(light: (0xD7D7D7, 1), dark: (0xFFFFFF, 0.13))
    static let hairline = dynamic(light: (0xEEEEEE, 1), dark: (0xFFFFFF, 0.06))

    /// Translucent interactive fills.
    static let fillActive = dynamic(light: (0x000000, 0.08), dark: (0xFFFFFF, 0.12))
    static let fillHover = dynamic(light: (0x000000, 0.05), dark: (0xFFFFFF, 0.08))
    static let fillSubtle = dynamic(light: (0x000000, 0.02), dark: (0xFFFFFF, 0.03))
    static let fillInput = dynamic(light: (0x000000, 0.04), dark: (0xFFFFFF, 0.06))
    static let borderInput = dynamic(light: (0x000000, 0.12), dark: (0xFFFFFF, 0.15))

    /// Primary button: black in light mode, white in dark mode.
    static let primary = dynamic(light: 0x191919, dark: 0xFFFFFF)
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x191919)

    /// Status tones, background + foreground.
    static let successBg = dynamic(light: (0x00A433, 0.1), dark: (0x10B981, 0.15))
    static let successFg = dynamic(light: (0x00713F, 0.87), dark: (0x6EE7B7, 1))
    static let errorBg = dynamic(light: (0xFF0008, 0.08), dark: (0xEF4444, 0.15))
    static let errorFg = dynamic(light: (0xC40006, 0.83), dark: (0xFCA5A5, 1))
    static let warningBg = dynamic(light: (0xFFDE00, 0.24), dark: (0xF59E0B, 0.15))
    static let warningFg = dynamic(light: (0xAB6400, 1), dark: (0xFCD34D, 1))
    static let infoBg = dynamic(light: (0x008FF5, 0.1), dark: (0x3B82F6, 0.15))
    static let infoFg = dynamic(light: (0x006DCB, 0.95), dark: (0x93C5FD, 1))

    /// Keyboard surfaces.
    static let keyboardBackground = dynamic(light: 0xF2F2F2, dark: 0x121212)
    static let key = dynamic(light: 0xFFFFFF, dark: 0x2A2A2A)
    static let keySpecial = dynamic(light: 0xDEDEDE, dark: 0x1E1E1E)
    static let keyPressed = dynamic(light: 0xD4D4D4, dark: 0x3A3A3A)

    /// The one accent: recording red.
    static let recording = dynamic(light: 0xE5484D, dark: 0xFF6369)
    /// Engine on and waiting: blue, so "ready" never looks like iOS's orange
    /// mic dot or like recording.
    static let ready = dynamic(light: 0x0B6BDE, dark: 0x4DA3FF)
    /// Transcribing: amber.
    static let working = dynamic(light: 0xAB6400, dark: 0xFFB224)

    /// Fixed colors for the Dynamic Island and Live Activity, which always
    /// sit on black.
    enum Island {
        static let ready = Color(red: 0x4D / 255, green: 0xA3 / 255, blue: 0xFF / 255)
        static let recording = Color(red: 0xFF / 255, green: 0x63 / 255, blue: 0x69 / 255)
        static let working = Color(red: 0xFF / 255, green: 0xB2 / 255, blue: 0x24 / 255)
    }

    // MARK: Shape

    static let controlRadius: CGFloat = 12
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 24
    /// One control height everywhere, at iOS's 44pt minimum tap target.
    static let controlHeight: CGFloat = 44

    // MARK: Type (Inter, bundled; falls back to the system font if missing)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Inter-Medium"
        case .semibold, .bold, .heavy, .black: name = "Inter-SemiBold"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    /// Big headings: Inter Display with tight tracking.
    static func display(_ size: CGFloat) -> Font {
        .custom("InterDisplay-Medium", size: size, relativeTo: .largeTitle)
    }

    // MARK: Helpers

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamic(light: (light, 1), dark: (dark, 1))
    }

    private static func dynamic(light: (UInt32, CGFloat), dark: (UInt32, CGFloat)) -> Color {
        Color(UIColor { traits in
            let (hex, alpha) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }
}

// MARK: - Components

/// A card: 24pt radius, 1pt outline, no fill, no shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

struct PageTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.display(28))
                .tracking(-0.7)
                .foregroundStyle(Theme.textEmphasis)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .semibold))
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(Theme.primary)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .medium))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.fillActive : Theme.fillInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Theme.borderInput, lineWidth: 1)
            )
    }
}

/// Hairline divider.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

/// Section header inside settings-style lists.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.font(11, .medium))
            .tracking(0.6)
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
