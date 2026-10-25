import SwiftUI

/// A status line, one round mic button, and the keys you can't say: switch
/// keyboards, space, delete, return. The whole middle of the keyboard is
/// the button's tap target, so it's hard to miss.
struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .frame(height: 30)
            if model.mode == .voice {
                MicArea(model: model)
                    .frame(maxHeight: .infinity)
                BottomRow(model: model)
            } else {
                KeyGrid(model: model)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.keyboardBackground)
        .onAppear {
            // Keyboards can't use UIApplication.open; SwiftUI's openURL is
            // one of the ways that still reaches the Yapper app.
            model.setSwiftUIOpen { url in openURL(url) }
        }
    }
}

// MARK: - Top bar

/// Engine state on the left; Cancel (recording) or Turn off (ready) on the right.
private struct TopBar: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(status)
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            Spacer(minLength: 8)
            if model.mode == .typing {
                Button { model.micTapped() } label: {
                    Label("Yap", systemImage: "mic.fill")
                        .font(Theme.font(13, .semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(Theme.primary))
                }
                .padding(.trailing, 4)
                .accessibilityLabel("Dictate")
            } else if model.phase == .recording {
                Button("Cancel") { model.cancelTapped() }
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textEmphasis)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
            } else if model.phase == .ready {
                Button { model.endSessionTapped() } label: {
                    Label("Turn off", systemImage: "power")
                        .font(Theme.font(13, .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .accessibilityLabel("Turn off the speech engine")
            }
        }
    }

    private var status: String {
        switch model.phase {
        case .recording: return "Listening"
        case .transcribing: return "Transcribing"
        case .ready, .preparing:
            if let ends = model.sessionEnds {
                return "Engine on until \(ends.formatted(date: .omitted, time: .shortened))"
            }
            return "Engine on"
        case .idle: return "Yapper"
        }
    }

    private var dotColor: Color {
        switch model.phase {
        case .recording: return Theme.recording
        case .transcribing, .preparing: return Theme.working
        case .ready: return Theme.ready
        case .idle: return Theme.textFaint
        }
    }
}

// MARK: - Mic

private struct MicArea: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Button { model.micTapped() } label: {
            VStack(spacing: 10) {
                MicRow(model: model)
                caption
                    .frame(height: 36, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MicPress())
        .disabled(model.phase == .transcribing)
        .animation(.easeInOut(duration: 0.15), value: model.phase)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var caption: some View {
        switch model.phase {
        case .recording:
            HStack(spacing: 6) {
                if let started = model.recordingStarted {
                    Text(timerInterval: started...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .foregroundStyle(Theme.recording)
                    Text("·").foregroundStyle(Theme.textFaint)
                }
                Text("Tap to finish").foregroundStyle(Theme.textEmphasis)
            }
            .font(Theme.font(15, .medium))
        case .transcribing:
            Text("Transcribing on your iPhone")
                .font(Theme.font(15, .medium))
                .foregroundStyle(Theme.textMuted)
        default:
            VStack(spacing: 2) {
                if model.banner == nil {
                    Text("Tap to talk")
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(Theme.textEmphasis)
                }
                Text(hint)
                    .font(Theme.font(12))
                    .foregroundStyle(model.banner == nil ? Theme.textMuted : Theme.errorFg)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var hint: String {
        if let banner = model.banner { return banner }
        if !model.hasFullAccess {
            return "Turn on Allow Full Access for Yapper in Settings to dictate."
        }
        if model.phase == .ready { return "Talks straight into this app" }
        return "Opens Yapper once to turn the engine on"
    }

    private var accessibilityLabel: String {
        switch model.phase {
        case .recording: return "Finish dictating"
        case .transcribing: return "Transcribing"
        default: return "Start dictating"
        }
    }
}

/// The mic between its two sets of bars. While recording it redraws every
/// display frame (up to 120 Hz), reading the level straight from the app;
/// otherwise the timeline is paused and nothing runs.
private struct MicRow: View {
    @ObservedObject var model: KeyboardModel
    @State private var meter = LevelMeter(barCount: LevelBars.count)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let recording = model.phase == .recording
        TimelineView(.animation(minimumInterval: nil, paused: !recording)) { context in
            let bars = recording
                ? meter.bars(at: context.date, feed: model.levelFeed, still: reduceMotion)
                : LevelBars.silent
            HStack(spacing: 14) {
                LevelBars(levels: bars, active: recording, mirrored: true)
                // The ring's pulse is decoration; Reduce Motion drops it.
                MicCircle(model: model, pulse: recording && !reduceMotion ? meter.level : 0)
                LevelBars(levels: bars, active: recording, mirrored: false)
            }
        }
        .onChange(of: recording) { meter.reset() }
    }
}

/// The round button itself.
private struct MicCircle: View {
    @ObservedObject var model: KeyboardModel
    /// The voice level, 0...1, for the ring.
    let pulse: Float

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            if model.phase == .recording {
                Circle()
                    .strokeBorder(Theme.recording.opacity(0.35), lineWidth: 6)
                    .scaleEffect(1 + CGFloat(min(pulse, 1)) * 0.25)
            }
            icon
        }
        // Smaller in landscape, where the keyboard is 70 points shorter.
        .frame(width: model.compact ? 56 : 76, height: model.compact ? 56 : 76)
    }

    private var fill: Color {
        model.phase == .recording ? Theme.recording : Theme.primary
    }

    @ViewBuilder
    private var icon: some View {
        switch model.phase {
        case .recording:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white)
                .frame(width: 22, height: 22)
        case .transcribing:
            ProgressView().tint(Theme.onPrimary)
        default:
            if model.waitingForApp {
                ProgressView().tint(Theme.onPrimary)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.onPrimary)
            }
        }
    }
}

private struct MicPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Bars that follow the input level, newest nearest the mic. Flat and faint
/// when not recording, so the layout never jumps. Drawn in one Canvas pass:
/// they change every frame, and nine views a side would be diffed every frame.
private struct LevelBars: View {
    static let count = 9
    static let silent = [Float](repeating: 0, count: count)
    private static let width: CGFloat = 4
    private static let spacing: CGFloat = 4
    private static let height: CGFloat = 48

    /// Newest first.
    let levels: [Float]
    let active: Bool
    /// The left side, where the newest bar is on the right, by the mic.
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            let color = active ? Theme.recording : Theme.textFaint.opacity(0.35)
            for (index, level) in levels.prefix(Self.count).enumerated() {
                let offset = CGFloat(index) * (Self.width + Self.spacing)
                let x = mirrored ? size.width - Self.width - offset : offset
                let height = max(Self.width, CGFloat(min(max(level, 0), 1)) * size.height)
                let bar = CGRect(x: x, y: (size.height - height) / 2, width: Self.width, height: height)
                context.fill(Capsule().path(in: bar), with: .color(color))
            }
        }
        .frame(width: CGFloat(Self.count) * Self.width + CGFloat(Self.count - 1) * Self.spacing, height: Self.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Bottom row

private struct BottomRow: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 6) {
            if model.needsGlobe {
                KeyButton(systemImage: "globe", label: "Next keyboard", width: 44) { model.nextKeyboard() }
            }
            KeyButton(systemImage: "keyboard", label: "Type with keys", width: 44) { model.showTyping() }
            if model.undoText != nil {
                KeyButton(systemImage: "arrow.uturn.backward", label: "Undo dictation", width: 44) { model.undoTapped() }
            }
            SpaceKey { model.space() }
            DeleteKey(model: model)
            KeyButton(text: model.returnLabel, label: "Return", width: 84, primary: model.returnIsPrimary) { model.returnKey() }
        }
        .frame(height: 44)
    }
}

private struct SpaceKey: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("space")
                .font(Theme.font(15, .medium))
                .foregroundStyle(Theme.textEmphasis)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.key))
        }
        .buttonStyle(KeyPress())
        .accessibilityLabel("Space")
    }
}

private struct KeyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct KeyButton: View {
    var systemImage: String?
    var text: String?
    let label: String
    var width: CGFloat = 52
    var primary = false
    let action: () -> Void

    init(systemImage: String, label: String, width: CGFloat = 52, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.width = width
        self.action = action
    }

    init(text: String, label: String, width: CGFloat, primary: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.label = label
        self.width = width
        self.primary = primary
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17))
                } else if let text {
                    Text(text).font(Theme.font(15, .medium))
                }
            }
            .foregroundStyle(primary ? Theme.onPrimary : Theme.textEmphasis)
            .frame(width: width, height: 44)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(primary ? Theme.primary : Theme.keySpecial)
            )
        }
        .buttonStyle(KeyPress())
        .accessibilityLabel(label)
    }
}

/// Deletes once on touch-down, then repeats; after a while it deletes
/// whole words.
private struct DeleteKey: View {
    @ObservedObject var model: KeyboardModel
    @State private var pressed = false
    @State private var timer: Timer?
    @State private var started: Date?

    var body: some View {
        Image(systemName: pressed ? "delete.left.fill" : "delete.left")
            .font(.system(size: 18))
            .foregroundStyle(Theme.textEmphasis)
            .frame(width: 52, height: 44)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(pressed ? Theme.keyPressed : Theme.keySpecial)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { begin() } }
                    .onEnded { _ in end() }
            )
            .accessibilityElement()
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.deleteBackward() }
    }

    private func begin() {
        pressed = true
        started = Date()
        model.deleteBackward()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let started else { return }
                let held = Date().timeIntervalSince(started)
                if held > 1.6 {
                    model.deleteWord()
                } else if held > 0.45 {
                    model.deleteBackward()
                }
            }
        }
    }

    private func end() {
        pressed = false
        started = nil
        timer?.invalidate()
        timer = nil
    }
}
