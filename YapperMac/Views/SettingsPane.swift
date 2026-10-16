import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var dictation: MacDictation
    @AppStorage("mac.trigger") private var trigger: TriggerKey = .fn
    @AppStorage("mac.sounds") private var sounds = true
    @AppStorage("mac.keepOnClipboard") private var keepOnClipboard = false
    @AppStorage("mac.inputDevice") private var inputDevice = ""
    @AppStorage(Settings.Key.removeFillers) private var removeFillers = true
    @AppStorage(Settings.Key.removeRepeats) private var removeRepeats = true
    @AppStorage(Settings.Key.historyDays) private var historyDays = -1
    @State private var recordingHours = Settings.recordingHours
    @State private var launchAtLogin = MacSettings.launchAtLogin
    @State private var inputs: [AudioInput] = []
    @State private var replacements = Settings.replacements
    @State private var newSpoken = ""
    @State private var newWritten = ""

    var body: some View {
        PaneScroll(title: "Settings") {
            Card {
                SectionLabel(text: "Dictation")
                SettingRow(title: "Dictation key", detail: "Hold to talk, or tap for hands-free.") {
                    Picker("", selection: $trigger) {
                        ForEach(TriggerKey.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                Hairline()
                SettingRow(title: "Microphone",
                           detail: "Pick the built-in microphone to keep AirPods sounding right while you dictate.") {
                    Picker("", selection: $inputDevice) {
                        Text("System default").tag("")
                        ForEach(inputs) { Text($0.name).tag($0.uid) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                Hairline()
                SettingRow(title: "Sounds", detail: "A soft tick when Yapper starts and stops listening.") {
                    Toggle("", isOn: $sounds).labelsHidden().toggleStyle(.switch)
                }
                Hairline()
                SettingRow(title: "Keep dictations on the clipboard",
                           detail: "Off: Yapper pastes, then puts back what you had copied before.") {
                    Toggle("", isOn: $keepOnClipboard).labelsHidden().toggleStyle(.switch)
                }
                Hairline()
                SettingRow(title: "Open at login") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, on in
                            MacSettings.launchAtLogin = on
                            launchAtLogin = MacSettings.launchAtLogin
                        }
                }
            }

            Card {
                SectionLabel(text: "Cleanup")
                SettingRow(title: "Remove filler words", detail: "um, uh, erm") {
                    Toggle("", isOn: $removeFillers).labelsHidden().toggleStyle(.switch)
                }
                Hairline()
                SettingRow(title: "Remove repeated words", detail: "“I I think” becomes “I think”.") {
                    Toggle("", isOn: $removeRepeats).labelsHidden().toggleStyle(.switch)
                }
            }

            Card {
                SectionLabel(text: "Dictionary")
                Text("When you say one thing, write another: names, jargon, the words a model gets wrong.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textMuted)
                ForEach(replacements) { item in
                    HStack {
                        Text(item.spoken).font(Theme.font(13)).foregroundStyle(Theme.textMuted)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                        Text(item.written).font(Theme.font(13, .medium)).foregroundStyle(Theme.textEmphasis)
                        Spacer()
                        Button {
                            replacements.removeAll { $0.id == item.id }
                            Settings.replacements = replacements
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("When I say", text: $newSpoken).textFieldStyle(.roundedBorder)
                    TextField("Write", text: $newWritten).textFieldStyle(.roundedBorder)
                    SmallButton(title: "Add") {
                        let spoken = newSpoken.trimmingCharacters(in: .whitespaces)
                        let written = newWritten.trimmingCharacters(in: .whitespaces)
                        guard !spoken.isEmpty, !written.isEmpty else { return }
                        replacements.append(Replacement(spoken: spoken, written: written))
                        Settings.replacements = replacements
                        newSpoken = ""
                        newWritten = ""
                    }
                }
            }

            Card {
                SectionLabel(text: "Kept on this Mac")
                SettingRow(title: "History", detail: "The text of each dictation.") {
                    Picker("", selection: $historyDays) {
                        Text("Forever").tag(-1)
                        Text("30 days").tag(30)
                        Text("7 days").tag(7)
                        Text("1 day").tag(1)
                        Text("Last one only").tag(0)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Hairline()
                SettingRow(title: "Recordings", detail: "The audio, for playing back. The text stays in History after it's gone.") {
                    Picker("", selection: $recordingHours) {
                        ForEach(Retention.recordingChoices, id: \.self) { Text(Retention.label(hours: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .onChange(of: recordingHours) { _, hours in
                        Settings.recordingHours = hours
                        RecordingStore.prune()
                    }
                }
            }

            Text("Yapper is free and open source. No account, no tracking: your voice and your words never leave this Mac.")
                .font(Theme.font(12))
                .foregroundStyle(Theme.textFaint)
        }
        .onAppear { inputs = AudioInput.all() }
    }
}
