import SwiftUI

/// The first-run steps: microphone, Accessibility, the key, a model, and a
/// place to try it.
struct SetupPane: View {
    @EnvironmentObject private var dictation: MacDictation
    @AppStorage("mac.trigger") private var trigger: TriggerKey = .fn
    @State private var tryText = ""

    var body: some View {
        PaneScroll(title: "Get started",
                   subtitle: "Hold a key in any app, talk, let go. Yapper types what you said, transcribed on this Mac.") {
            Card {
                SectionLabel(text: "Permissions")
                SettingRow(title: "Microphone",
                           detail: "Only on while you hold the key. macOS shows its orange dot whenever Yapper listens.") {
                    switch dictation.micPermission {
                    case .granted: StatusTag(text: "Allowed", tone: .good)
                    default: SmallButton(title: "Allow", primary: true) { Task { await dictation.requestMicrophone() } }
                    }
                }
                Hairline()
                SettingRow(title: "Accessibility",
                           detail: "Lets Yapper notice the dictation key in other apps and paste the text where your cursor is. Turn Yapper on in the list System Settings opens.") {
                    if dictation.isTrusted {
                        StatusTag(text: "Allowed", tone: .good)
                    } else {
                        SmallButton(title: "Open Settings", primary: true) { dictation.requestAccessibility() }
                    }
                }
            }

            Card {
                SectionLabel(text: "Dictation key")
                SettingRow(title: "Hold to talk",
                           detail: "Hold the key while you talk and let go to finish. Or tap it once to talk hands-free, and tap again when you're done. Esc cancels.") {
                    Picker("", selection: $trigger) {
                        ForEach(TriggerKey.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                if trigger == .fn, !MacSettings.globeKeyIsFree {
                    Hairline()
                    SettingRow(title: "Set the fn key to do nothing on its own",
                               detail: "In System Settings › Keyboard, set “Press 🌐 key to” to “Do Nothing”, or the emoji picker or Apple's dictation opens every time you use Yapper.") {
                        SmallButton(title: "Keyboard Settings") { dictation.openKeyboardSettings() }
                    }
                }
            }

            Card {
                SectionLabel(text: "Speech model")
                SettingRow(title: ModelChoice.current.title, detail: modelDetail) {
                    SmallButton(title: "Change") { MainWindowController.shared.show(.model) }
                }
            }

            Card {
                SectionLabel(text: "Try it")
                Text(dictation.isSetUp
                     ? "Click in the box, hold \(trigger.shortName) and say something."
                     : "Allow the microphone and Accessibility above first.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textMuted)
                TextEditor(text: $tryText)
                    .font(Theme.font(14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 90)
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.fillInput))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderInput))
            }
        }
    }

    private var modelDetail: String {
        let choice = ModelChoice.current
        if choice == .apple {
            return dictation.appleReady
                ? "Ready. Built into macOS, starts instantly."
                : "Needs a one-time setup on the Speech model page."
        }
        switch dictation.modelState {
        case .ready: return "Ready on the Neural Engine."
        case .loading: return "Loading into the Neural Engine…"
        case let .downloading(progress, label): return "\(label) · \(Int(progress * 100))%"
        case .notDownloaded: return "Not downloaded yet."
        case let .failed(message): return message
        }
    }
}
