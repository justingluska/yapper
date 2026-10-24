import SwiftUI

/// Home's one control: a big round power button for the speech engine. Off is
/// a plain surface with a hairline; on is lit in the engine's color with a
/// slow, soft glow; a ring around it fills while the model loads.
struct PowerButton: View {
    enum Look: Equatable {
        case off
        /// A call or Siri took the microphone and switched the engine off.
        case paused
        /// On: blue when ready, red while listening, amber while typing,
        /// like the Dynamic Island.
        case lit(Color)
    }

    let look: Look
    /// 0...1 while the model loads, for the ring around the button.
    var progress: Double?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size: CGFloat = 196
    private static let ringGap: CGFloat = 14
    private static let ringWidth: CGFloat = 3

    var body: some View {
        Button(action: action) {
            ZStack {
                glow
                Circle().fill(fill)
                Circle().strokeBorder(stroke, lineWidth: look == .paused ? 1.5 : 1)
                Image(systemName: "power")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(glyph)
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .background(ring)
        .animation(.easeInOut(duration: 0.35), value: look)
    }

    // MARK: Parts

    @ViewBuilder
    private var glow: some View {
        if case let .lit(color) = look {
            let halo = Circle()
                .fill(color)
                .blur(radius: 34)
            if reduceMotion {
                halo.opacity(0.35).scaleEffect(1.06)
            } else {
                halo.phaseAnimator([false, true]) { view, out in
                    view
                        .opacity(out ? 0.5 : 0.24)
                        .scaleEffect(out ? 1.16 : 1.0)
                } animation: { _ in
                    .easeInOut(duration: 2.8)
                }
            }
        }
    }

    /// The track around the button, while it's lit or loading, and the
    /// loading progress on it. Off and paused, the button stands alone.
    private var ring: some View {
        let diameter = Self.size + Self.ringGap * 2
        return ZStack {
            Circle()
                .stroke(track, lineWidth: Self.ringWidth)
                .opacity(showsTrack ? 1 : 0)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(Theme.ready, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    // MARK: Colors

    private var fill: Color {
        if case let .lit(color) = look { return color }
        return Theme.surface
    }

    private var stroke: Color {
        switch look {
        case .off: return Theme.border
        case .paused: return Theme.warningFg
        case .lit: return .clear
        }
    }

    private var glyph: Color {
        switch look {
        case .off: return progress == nil ? Theme.textMuted : Theme.ready
        case .paused: return Theme.warningFg
        case .lit: return .white
        }
    }

    private var showsTrack: Bool {
        if case .lit = look { return true }
        return progress != nil
    }

    private var track: Color {
        if case let .lit(color) = look { return color.opacity(progress == nil ? 0.18 : 0.12) }
        return Theme.hairline
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}
