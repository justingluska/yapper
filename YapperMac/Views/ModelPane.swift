import SwiftUI

/// Pick the speech model: Apple's, built in, or a Parakeet download.
struct ModelPane: View {
    @EnvironmentObject private var dictation: MacDictation
    @AppStorage(Settings.Key.parakeetOnly) private var parakeetOnly = false

    var body: some View {
        PaneScroll(title: "Speech model",
                   subtitle: "Everything runs on this Mac. Models download once, then Yapper works offline.") {
            Card {
                ForEach(Array(ModelChoice.allCases.enumerated()), id: \.element) { index, choice in
                    if index > 0 { Hairline() }
                    row(choice)
                }
            }
            Card {
                SettingRow(title: "Only use Parakeet",
                           detail: "Never fall back to Apple's model while Parakeet isn't ready; the dictation fails with a clear message instead.") {
                    Toggle("", isOn: $parakeetOnly).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .task { await dictation.refreshApple() }
    }

    @ViewBuilder
    private func row(_ choice: ModelChoice) -> some View {
        let selected = ModelChoice.current == choice
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(title: choice.title, detail: detail(choice)) {
                HStack(spacing: 8) {
                    status(choice, selected: selected)
                    actions(choice, selected: selected)
                }
            }
            if dictation.downloading == choice, case let .downloading(progress, label) = dictation.modelState {
                ProgressView(value: progress) {
                    Text("\(label) · \(Int(progress * 100))%")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.textMuted)
                }
                .tint(Theme.ready)
            }
            if choice == .apple, let progress = dictation.appleInstallProgress {
                ProgressView(value: progress).tint(Theme.ready)
            }
        }
    }

    private func detail(_ choice: ModelChoice) -> String {
        switch choice {
        case .apple:
            return "Built into macOS: nothing to download, starts instantly. On macOS 26 and later it's Apple's newer model, the one behind Notes transcription."
        case .ultra:
            return "The most accurate. 632 MB download. 25 languages, runs on the Neural Engine."
        case .v3:
            return "The previous Parakeet. 480 MB download, 25 languages."
        }
    }

    @ViewBuilder
    private func status(_ choice: ModelChoice, selected: Bool) -> some View {
        if selected {
            switch (choice.isParakeet, dictation.modelState) {
            case (true, .loading): StatusTag(text: "Loading", tone: .working)
            case (true, .failed): StatusTag(text: "Failed", tone: .bad)
            case (false, _) where !dictation.appleReady: StatusTag(text: "Needs setup", tone: .working)
            default: StatusTag(text: "In use", tone: .good)
            }
        } else if choice.isParakeet, dictation.downloadedModels.contains(choice) {
            StatusTag(text: "Downloaded")
        }
    }

    @ViewBuilder
    private func actions(_ choice: ModelChoice, selected: Bool) -> some View {
        if choice == .apple {
            if dictation.appleState == .notInstalled, dictation.appleInstallProgress == nil {
                SmallButton(title: "Download", primary: selected) { Task { await dictation.installAppleModel() } }
            } else if dictation.appleState == .unsupported, !dictation.speechAuthorized {
                SmallButton(title: "Allow", primary: selected) { Task { await dictation.requestSpeech() } }
            }
            if !selected {
                SmallButton(title: "Use") { Task { await dictation.select(.apple) } }
            }
        } else if dictation.downloadedModels.contains(choice) {
            if !selected {
                SmallButton(title: "Use") { Task { await dictation.select(choice) } }
            }
            SmallButton(title: "Delete") { Task { await dictation.delete(choice) } }
        } else if dictation.downloading != choice {
            SmallButton(title: "Download \(choice.downloadMB) MB", primary: choice == .ultra) {
                Task { await dictation.download(choice) }
            }
            .disabled(dictation.downloading != nil)
        }
    }
}
