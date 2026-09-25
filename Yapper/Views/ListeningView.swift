import SwiftUI

/// Full screen while recording, and the "go back" screen after a keyboard
/// dictation. The keyboard can't use the microphone, so it opens Yapper; this
/// is where the user lands, and it has to say plainly how to get back.
struct ListeningView: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer()
                center
                Spacer()
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        HStack {
            Text(statusText)
                .font(Theme.font(14, .medium))
                .foregroundStyle(controller.phase == .recording ? Theme.recording : Theme.textMuted)
            Spacer()
            if controller.phase == .recording {
                Button("Cancel") { controller.cancelRecording() }
                    .font(Theme.font(15, .medium))
                    .foregroundStyle(Theme.textMuted)
            } else {
                Button("Close") { controller.markReturned() }
                    .font(Theme.font(15, .medium))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    @ViewBuilder
    private var center: some View {
        switch controller.phase {
        case .recording:
            VStack(spacing: 28) {
                if let started = controller.recordingStarted {
                    Text(timerInterval: started...Date.distantFuture, countsDown: false)
                        .font(Theme.font(17, .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textMuted)
                }
                Waveform(level: controller.level)
                    .frame(height: 96)
                Button {
                    controller.finishRecording()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 240)
            }
        case .transcribing:
            VStack(spacing: 16) {
                ProgressView()
                Text(controller.waitingForModel
                     ? "Getting \(ModelChoice.current.title) ready, then transcribing…"
                     : "Transcribing on your iPhone…")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.textMuted)
            }
        default:
            if let text = controller.lastText, controller.errorMessage == nil {
                Card {
                    SectionLabel(text: "Ready to insert")
                    Text(text)
                        .font(Theme.font(17))
                        .foregroundStyle(Theme.textEmphasis)
                        .lineLimit(6)
                }
            } else if let error = controller.errorMessage {
                Card {
                    Text(error)
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.text)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if controller.recordingSource == .keyboard {
                SwipeBackHint()
                Text(Settings.copyEveryDictation
                     ? "Your text will be waiting in the Yapper keyboard, and it's on the clipboard too. The engine stays on, so next time you won't come here."
                     : "Your text will be waiting in the Yapper keyboard. The engine stays on, so next time you won't come here.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
            } else if controller.phase == .ready, controller.lastText != nil, controller.errorMessage == nil {
                Text("Copied. Paste it anywhere.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusText: String {
        switch controller.phase {
        case .recording: return "● Listening"
        case .transcribing: return "Transcribing"
        default: return "Mic ready"
        }
    }
}

/// "Swipe right along the bottom edge", with a small animated arrow.
struct SwipeBackHint: View {
    @State private var nudge = false

    var body: some View {
        VStack(spacing: 10) {
            Text("Swipe right along the bottom edge to go back")
                .font(Theme.font(17, .semibold))
                .foregroundStyle(Theme.textEmphasis)
                .multilineTextAlignment(.center)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillActive).frame(width: 140, height: 5)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textEmphasis)
                    .offset(x: nudge ? 120 : 0, y: -16)
                    .opacity(nudge ? 0 : 1)
            }
            .frame(width: 140, height: 36, alignment: .bottomLeading)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { nudge = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bars that follow the input level, newest on the right.
struct Waveform: View {
    let level: Float
    @State private var history: [Float] = Array(repeating: 0, count: 40)

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(history.indices, id: \.self) { index in
                    Capsule()
                        .fill(Theme.textEmphasis)
                        .frame(height: max(4, CGFloat(history[index]) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: level) { _, value in
            history.removeFirst()
            history.append(value)
        }
        .accessibilityHidden(true)
    }
}
