import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct YapperWidgetBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
        StartDictationControl()
    }
}

/// Lock Screen + Dynamic Island while a session keeps the mic warm. It's the
/// honest answer to iOS's orange dot, whose color no app can change: what is
/// listening, in Yapper's own colors (blue ready, red listening, amber
/// typing), and how to turn it off.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let look = Look(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Glyph(look: look, size: 30)
                        Text("Yapper")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EndButton()
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Headline(state: context.state, look: look)
                        StatusLine(state: context.state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Glyph(look: look, size: 22)
            } compactTrailing: {
                CompactTrailing(state: context.state, look: look)
            } minimal: {
                Glyph(look: look, size: 22)
            }
            .keylineTint(look.color)
        }
    }
}

/// Color, symbol and word for a phase.
private struct Look {
    let color: Color
    let symbol: String
    let word: String

    init(_ state: SessionAttributes.ContentState) {
        switch state.phase {
        case "recording":
            color = Theme.Island.recording
            symbol = "waveform"
            word = "Listening"
        case "transcribing", "preparing":
            color = Theme.Island.working
            symbol = "text.cursor"
            word = "Typing"
        default:
            color = Theme.Island.ready
            symbol = "mic.fill"
            word = "Yap"
        }
    }
}

/// A filled circle in the phase's color with the symbol on it.
private struct Glyph: View {
    let look: Look
    let size: CGFloat

    var body: some View {
        Image(systemName: look.symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Circle().fill(look.color))
    }
}

private struct CompactTrailing: View {
    let state: SessionAttributes.ContentState
    let look: Look

    var body: some View {
        Group {
            if state.phase == "recording", let started = state.recordingStarted {
                Text(timerInterval: started...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(width: 42)
            } else {
                Text(look.word)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(look.color)
    }
}

private struct Headline: View {
    let state: SessionAttributes.ContentState
    let look: Look

    var body: some View {
        Group {
            switch state.phase {
            case "recording":
                if let started = state.recordingStarted {
                    HStack(spacing: 6) {
                        Text("Listening")
                        Text(timerInterval: started...Date.distantFuture, countsDown: false).monospacedDigit()
                    }
                } else {
                    Text("Listening")
                }
            case "transcribing", "preparing":
                Text("Typing it out")
            default:
                Text("Ready to yap")
            }
        }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(look.color)
        .lineLimit(1)
    }
}

private struct LockScreenView: View {
    let state: SessionAttributes.ContentState

    var body: some View {
        let look = Look(state)
        HStack(spacing: 14) {
            Glyph(look: look, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Headline(state: state, look: look)
                StatusLine(state: state)
            }
            Spacer()
            EndButton()
        }
        .padding(16)
    }
}

private struct StatusLine: View {
    let state: SessionAttributes.ContentState

    var body: some View {
        Group {
            switch state.phase {
            case "recording":
                Text("Tap the mic on the Yapper keyboard to finish")
            case "transcribing", "preparing":
                Text("Transcribing on your iPhone")
            default:
                if let ends = state.sessionEnds {
                    Text("Engine on until \(ends.formatted(date: .omitted, time: .shortened)). Tap the Yapper keyboard.")
                } else {
                    Text("Engine on. Tap the Yapper keyboard.")
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.75))
        .lineLimit(1)
    }
}

private struct EndButton: View {
    var body: some View {
        Button(intent: EndSessionIntent()) {
            Label("Off", systemImage: "power")
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .accessibilityLabel("Turn off the speech engine")
    }
}

/// Control Center / Lock Screen / Action Button control.
struct StartDictationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.gluska.yapper.start-dictation") {
            ControlWidgetButton(action: StartDictationIntent()) {
                Label("Yap", systemImage: "mic.fill")
            }
        }
        .displayName("Start Dictating")
        .description("Opens Yapper and starts listening.")
    }
}
