import AppKit
import SwiftUI

/// What opens from the menu bar icon.
struct MenuView: View {
    @EnvironmentObject private var dictation: MacDictation
    @AppStorage("mac.trigger") private var trigger: TriggerKey = .fn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Yapper")
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.textEmphasis)
                Spacer()
                StatusTag(text: statusText, tone: statusTone)
            }

            if dictation.isSetUp {
                Text("Hold \(trigger.shortName) to dictate. Tap it for hands-free.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textMuted)
            } else {
                Text("Yapper needs the microphone and Accessibility before it can type for you.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textMuted)
                SmallButton(title: "Finish setup", primary: true) { MainWindowController.shared.show(.setup) }
            }

            if let text = dictation.lastText {
                Hairline()
                Text(text)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                SmallButton(title: "Copy last dictation") { dictation.copy(text) }
            }

            Hairline()
            HStack(spacing: 8) {
                SmallButton(title: dictation.phase == .recording ? "Stop" : "Dictate") { dictation.toggleFromMenu() }
                    .disabled(dictation.phase == .transcribing || !dictation.isSetUp)
                SmallButton(title: "Open Yapper") { MainWindowController.shared.show() }
                Spacer()
                SmallButton(title: "Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { dictation.refreshPermissions() }
    }

    private var statusText: String {
        switch dictation.phase {
        case .recording: return "Listening"
        case .transcribing: return "Transcribing"
        case .idle:
            if !dictation.isSetUp { return "Setup needed" }
            switch dictation.modelState {
            case .loading: return "Loading model"
            case .downloading: return "Downloading"
            default: return "Ready"
            }
        }
    }

    private var statusTone: StatusTag.Tone {
        switch dictation.phase {
        case .recording: return .bad
        case .transcribing: return .working
        case .idle: return dictation.isSetUp ? .good : .working
        }
    }
}
