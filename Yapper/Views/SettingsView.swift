import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var sessionMinutes = Settings.sessionMinutes
    @State private var removeFillers = Settings.removeFillers
    @State private var removeRepeats = Settings.removeRepeats
    @State private var haptics = Settings.haptics
    @State private var historyDays = Settings.historyDays
    @State private var copyEveryDictation = Settings.copyEveryDictation
    @State private var recordingDays = Settings.recordingDays

    var body: some View {
        Form {
            Section {
                StatsView()
            } header: {
                SectionLabel(text: "Your stats")
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            Section {
                HStack {
                    Text("Speech engine")
                    Spacer()
                    SessionToggle()
                }
                Picker("Turn off after", selection: $sessionMinutes) {
                    ForEach(Settings.sessionChoices, id: \.self) { minutes in
                        Text(label(minutes)).tag(minutes)
                    }
                }
                .onChange(of: sessionMinutes) { _, value in Settings.sessionMinutes = value }
                NavigationLink("How it works") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            PageTitle(title: "How the speech engine works")
                            HowItWorks()
                        }
                        .padding(20)
                    }
                    .background(Theme.background)
                }
            } header: {
                SectionLabel(text: "Speech engine")
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let problem = controller.liveActivityProblem {
                        Text(problem).foregroundStyle(Theme.errorFg)
                    }
                    Text("While the engine is on, the keyboard dictates without opening Yapper, and the Dynamic Island shows it in blue (red while listening). iOS also shows its orange mic dot the whole time; apps can't change that one.")
                }
                .padding(.top, 4)
            }

            ModelsSection()

            Section {
                Toggle("Remove um, uh and er", isOn: $removeFillers)
                    .onChange(of: removeFillers) { _, value in Settings.removeFillers = value }
                Toggle("Remove stutters (\"I I think\")", isOn: $removeRepeats)
                    .onChange(of: removeRepeats) { _, value in Settings.removeRepeats = value }
            } header: {
                SectionLabel(text: "Cleanup")
            }

            Section {
                Picker("Keep text", selection: $historyDays) {
                    Text("Last dictation only").tag(0)
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Forever").tag(-1)
                }
                .onChange(of: historyDays) { _, value in
                    Settings.historyDays = value
                    HistoryStore.save(HistoryStore.prune(HistoryStore.load()))
                    RecordingStore.prune()
                    controller.historyChanged()
                }
                Picker("Keep recordings", selection: $recordingDays) {
                    Text("Don't keep").tag(0)
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Forever").tag(-1)
                }
                .onChange(of: recordingDays) { _, value in
                    Settings.recordingDays = value
                    RecordingStore.prune()
                    controller.historyChanged()
                }
            } header: {
                SectionLabel(text: "History")
            } footer: {
                Text("Text is every dictation's words, including the ones that failed. Recordings are the audio, kept so you can play a dictation back or transcribe it again. Both stay on this iPhone.")
            }

            Section {
                Toggle("Copy every dictation", isOn: $copyEveryDictation)
                    .onChange(of: copyEveryDictation) { _, value in Settings.copyEveryDictation = value }
                Toggle("Haptics", isOn: $haptics)
                    .onChange(of: haptics) { _, value in Settings.haptics = value }
            } header: {
                SectionLabel(text: "General")
            } footer: {
                Text("Copy every dictation puts what you said on the clipboard as well as typing it, so you can paste it again anywhere.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Made by Justin Gluska")
                        .font(Theme.font(16, .semibold))
                        .foregroundStyle(Theme.textEmphasis)
                    Text("Yapper is completely free, made for the community of people who dictate all day. If you like it, give me a follow.")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.text)
                    NavigationLink("How Yapper is different") { DifferentView() }
                        .font(Theme.font(15, .medium))
                    NavigationLink("Good to know") { GoodToKnowView() }
                        .font(Theme.font(15, .medium))
                    Link("@gluska on X", destination: URL(string: "https://x.com/gluska")!)
                        .font(Theme.font(15, .medium))
                }
                .padding(.vertical, 4)
            } header: {
                SectionLabel(text: "About")
            }

            Section {
                Button("Keyboard settings") { KeyboardStatus.openSettings() }
                Button("Action Button and Control Center") { showActionButtonHelp = true }
                NavigationLink("Privacy") { PrivacyView() }
                Link("Privacy policy", destination: URL(string: "https://goldpenguin.org/yapper/privacy/")!)
                Link("Terms of service", destination: URL(string: "https://goldpenguin.org/yapper/terms/")!)
                Link("Support", destination: URL(string: "https://goldpenguin.org/yapper/support/")!)
                NavigationLink("Licenses") { LicensesView() }
                Link("Source code", destination: URL(string: "https://github.com/justingluska/yapper")!)
            } footer: {
                Text("Yapper \(appVersion). Open source, MIT license.")
            }
        }
        .font(Theme.font(16))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listSectionSpacing(24)
        .navigationTitle("Settings")
        .onAppear { controller.refreshDownloadedModels() }
        .alert("Action Button, Control Center and Back Tap", isPresented: $showActionButtonHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Action Button: Settings › Action Button › Shortcut › Yapper › Start Dictating.\n\nControl Center: edit Control Center › Add a Control › Yapper.\n\nBack Tap: Settings › Accessibility › Touch › Back Tap › Start Dictating.\n\nYapper opens, listens, and copies your words when you tap Done.")
        }
    }

    @State private var showActionButtonHelp = false

    private func label(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Until I end it"
        case 60: return "1 hour"
        default: return "\(minutes) minutes"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(title: "Privacy", subtitle: "Short version: nothing leaves your iPhone.")
                block("What Yapper collects", "Nothing. There is no account, no analytics, no advertising, no crash reporting and no server.")
                block("Your voice", "Audio is recorded only while you dictate and transcribed on this iPhone. Each recording is kept on this iPhone for 1 day by default (Settings › Keep recordings, from Don't keep to Forever) so you can play it back or transcribe it again, then deleted. Recordings are never sent anywhere and are left out of iCloud backups.")
                block("Your text", "Transcripts, including failed attempts, are kept in History on this device for as long as you choose in Settings, and you can delete them at any time. If your iPhone backs up to iCloud, iOS includes app data like History in that backup, as for any app.")
                block("The internet", "Yapper downloads the speech model once, from Hugging Face, when you ask it to. After that it makes no network requests. The keyboard has no network code at all.")
                block("Full Access", "iOS requires Full Access for the keyboard to share text with the Yapper app through their private App Group folder. Yapper uses it for that and nothing else.")
                block("Check for yourself", "Yapper is open source: github.com/justingluska/yapper")
            }
            .padding(20)
        }
        .background(Theme.background)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(16, .semibold)).foregroundStyle(Theme.textEmphasis)
            Text(text).font(Theme.font(15)).foregroundStyle(Theme.text)
        }
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(title: "Licenses")
                entry("Parakeet Ultra speech model",
                      "Moondream's post-training of NVIDIA Parakeet TDT 0.6B v3. Licensed under CC BY 4.0 (creativecommons.org/licenses/by/4.0). Core ML conversion by FluidInference. Yapper runs the model unmodified.")
                entry("Parakeet TDT 0.6B v3 speech model",
                      "NVIDIA Corporation. Licensed under CC BY 4.0 (creativecommons.org/licenses/by/4.0). Core ML conversion by FluidInference. Yapper runs the model unmodified.")
                entry("FluidAudio", "Copyright FluidInference. Apache License 2.0.", file: "Apache-2.0")
                entry("NeMo text processing", "Bundled with FluidAudio. Apache License 2.0.", file: "Apache-2.0")
                entry("Inter typeface", "Copyright The Inter Project Authors. SIL Open Font License 1.1.", file: "Inter-LICENSE")
                entry("Yapper", "Copyright Justin Gluska. MIT License.")
            }
            .padding(20)
        }
        .background(Theme.background)
    }

    private func entry(_ title: String, _ text: String, file: String? = nil) -> some View {
        Card {
            Text(title).font(Theme.font(16, .semibold)).foregroundStyle(Theme.textEmphasis)
            Text(text).font(Theme.font(14)).foregroundStyle(Theme.textMuted)
            if let file {
                NavigationLink("Full license text") { LicenseTextView(title: title, file: file) }
                    .font(Theme.font(14, .medium))
            }
        }
    }
}

/// A bundled license file, shown in full.
struct LicenseTextView: View {
    let title: String
    let file: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "License text missing." }
        return text
    }
}

/// Local versus cloud dictation, in plain words.
struct DifferentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(title: "How Yapper is different", subtitle: "Same idea as other dictation apps. The work happens somewhere else.")
                block("Most dictation apps work in the cloud",
                      "When you talk, they upload your recording to their servers, a model there turns it into text, and the text comes back. That's why they need an account and a connection, why many cap your words per week, and why your voice and text end up on someone else's computer, often with analytics attached.")
                block("Yapper works on your iPhone",
                      "The speech model runs on your iPhone's Neural Engine, the chip built for this. Your voice is turned into text right there. There's no Yapper server at all: no account, no word limits, no subscription, and it works in airplane mode.")
                block("The trade-off",
                      "The model has to live on your phone: a one-time download of about 600 MB, and a few seconds to load it when you turn the engine on (a few minutes the very first time, while iOS optimizes it). Cloud apps skip that, but only because your audio leaves your phone.")
                block("Nothing to take our word for",
                      "Yapper is open source, so anyone can read the code and check that it never sends your voice or text anywhere. The only network request it ever makes is the model download you start yourself.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(16, .semibold)).foregroundStyle(Theme.textEmphasis)
            Text(text).font(Theme.font(15)).foregroundStyle(Theme.text)
        }
    }
}
