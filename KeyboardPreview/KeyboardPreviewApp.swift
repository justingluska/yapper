import SwiftUI

/// Shows the Yapper keyboard's layout in one state, at the real keyboard's
/// height, under a sample text field. Only the screenshot tests use it
/// (scheme YapperScreens); it never ships.
///
/// Launch arguments: `-state idle|ready|recording|transcribing|undo|error`,
/// `-dark`, `-landscape` (compact height).
@main
struct KeyboardPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            PreviewScreen()
        }
    }
}

private struct PreviewScreen: View {
    private let arguments = ProcessInfo.processInfo.arguments
    @StateObject private var model: KeyboardModel
    private let timer = Timer.publish(every: 0.07, on: .main, in: .common).autoconnect()
    @State private var tick = 0.0

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let state = arguments.firstIndex(of: "-state").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "idle"
        let compact = arguments.contains("-landscape")
        let ends = Calendar.current.date(bySettingHour: 15, minute: 40, second: 0, of: Date())
        let model: KeyboardModel
        switch state {
        case "ready": model = KeyboardModel(preview: .ready, sessionEnds: ends, compact: compact)
        case "recording": model = KeyboardModel(preview: .recording, sessionEnds: ends, compact: compact)
        case "transcribing": model = KeyboardModel(preview: .transcribing, sessionEnds: ends, compact: compact)
        case "undo": model = KeyboardModel(preview: .ready, sessionEnds: ends, undo: "See you at six.", compact: compact)
        case "error": model = KeyboardModel(preview: .idle, banner: "Didn't catch anything. Try again a little closer to the mic.", compact: compact)
        case "typing": model = KeyboardModel(preview: .ready, sessionEnds: ends, compact: compact, mode: .typing)
        default: model = KeyboardModel(preview: .idle, compact: compact)
        }
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Messages")
                    .font(Theme.font(17, .semibold))
                    .foregroundStyle(Theme.textEmphasis)
                Text("Hey, are we still on for dinner tonight?")
                    .font(Theme.font(16))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.fillInput))
                Spacer()
                Text("Sounds good, see you at six.")
                    .font(Theme.font(16))
                    .foregroundStyle(Theme.textEmphasis)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.borderInput))
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(Theme.background)

            KeyboardRootView(model: model)
                .frame(height: KeyboardMetrics.height(compact: model.compact))
                .padding(.bottom, 34)
                .background(Theme.keyboardBackground)
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(arguments.contains("-dark") ? .dark : .light)
        .onReceive(timer) { _ in
            // A believable voice level for the recording state's bars.
            tick += 0.07
            let value = 0.25 + 0.35 * abs(sin(tick * 3.1)) + 0.25 * abs(sin(tick * 7.3))
            model.previewLevel(Float(min(value, 1)))
        }
    }
}
