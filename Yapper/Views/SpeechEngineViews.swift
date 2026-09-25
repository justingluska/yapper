import SwiftUI

/// Home's speech engine card: the on/off switch for a session, which model
/// does the work, and how it all works.
struct SpeechEngineCard: View {
    @EnvironmentObject private var controller: DictationController
    @State private var showHow = false

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Speech engine")
                    Text(title)
                        .font(Theme.display(24))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.textEmphasis)
                }
                Spacer()
                SessionToggle()
            }

            Text(statusText)
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if let problem = controller.liveActivityProblem {
                Text(problem)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.errorFg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NavigationLink {
                ModelsView()
            } label: {
                ModelSummaryRow()
            }
            .buttonStyle(.plain)

            Button {
                if controller.isSessionLive || controller.startSession() {
                    controller.beginRecording(source: .app)
                }
            } label: {
                Label("Dictate and copy", systemImage: "mic.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            if let error = controller.errorMessage, controller.phase != .recording {
                Text(error)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.errorFg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showHow.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("How it works")
                        .font(Theme.font(14, .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showHow ? 180 : 0))
                    Spacer()
                }
                .foregroundStyle(Theme.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showHow {
                HowItWorks()
                    .transition(.opacity)
            }
        }
    }

    private var isLoading: Bool {
        controller.isSessionLive && controller.modelState == .loading
    }

    private var title: String {
        if isLoading { return "Starting" }
        return controller.isSessionLive ? "On" : "Off"
    }

    private var statusText: String {
        if isLoading {
            return "Loading \(ModelChoice.current.title) onto your iPhone's Neural Engine. You can already dictate; your first words are transcribed as soon as it's ready."
        }
        if controller.isSessionLive {
            if let ends = controller.sessionEnds {
                return "Listening for the keyboard until \(ends.formatted(date: .omitted, time: .shortened)). Tap the Yapper keyboard in any app and talk; you won't come back here."
            }
            return "Listening for the keyboard until you turn it off. Tap the Yapper keyboard in any app and talk; you won't come back here."
        }
        return "Turned off. Nothing is listening and no model is in memory. Turn it on before you start writing, or just tap the Yapper keyboard: the first tap opens Yapper once to turn it on."
    }
}

/// The session switch. On starts the microphone and loads the model; off
/// releases both.
struct SessionToggle: View {
    @EnvironmentObject private var controller: DictationController
    @State private var firstLoadNote = false

    var body: some View {
        Toggle("Speech engine", isOn: Binding(
            get: { controller.isSessionLive },
            set: { on in
                if on {
                    // Checked before starting: starting begins the load.
                    let slow = controller.needsFirstLoad
                    if controller.startSession(), slow { firstLoadNote = true }
                } else {
                    controller.endSession()
                }
            }
        ))
        .labelsHidden()
        .tint(Theme.ready)
        .accessibilityLabel("Speech engine")
        .alert("Loading \(ModelChoice.current.title)", isPresented: $firstLoadNote) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This is the first time this model runs on your iPhone, so iOS is optimizing it for your Neural Engine. That can take a few minutes, once. After this it loads in a few seconds.\n\nYou can keep using your phone. The Dynamic Island turns blue when the engine is ready.")
        }
    }
}

/// Plain-words explanation of the session, and why it exists.
struct HowItWorks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            point("Everything stays on this iPhone.",
                  "Your voice is turned into text by the model on the Neural Engine. Nothing is uploaded.")
            point("Why there's an on switch.",
                  "iOS never lets a keyboard use the microphone, and only lets an app turn the microphone on while it's on screen. So the Yapper app does the listening, and it has to be switched on from the foreground once. After that it keeps running in the background and the keyboard dictates instantly. Every dictation keyboard on iPhone works this way.")
            point("Why is it slow to start?",
                  "Turning the engine on loads the speech model into your iPhone's Neural Engine. The very first time, iOS also optimizes the model for your exact chip, which can take a few minutes. It keeps the result, so after that the engine starts in a few seconds. Turning the engine off takes the model back out of memory, which is why it isn't instant every time.")
            point("Why cloud apps feel quicker to start.",
                  "They send your audio to a server, so there's no model on the phone to get ready. Yapper does the work on your iPhone instead: once the model is loaded it's just as fast, it works offline, and your voice never leaves the phone. If you want instant starts, choose Apple on-device in Settings: nothing to load, less accurate.")
            point("The orange dot.",
                  "iOS shows it the whole time the engine is on, and apps can't change its color. Yapper's own sign is in the Dynamic Island: blue while the engine is ready, red while it's listening, amber while it types. Yapper only keeps audio while you're dictating, and the engine switches itself off after the time you choose in Settings, or when you turn it off here, in the keyboard, or from the Dynamic Island.")
        }
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.font(14, .semibold))
                .foregroundStyle(Theme.textEmphasis)
            Text(text)
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One line on Home: which model, and whether it's ready. Opens the model list.
struct ModelSummaryRow: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 17))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelChoice.current.title)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.textEmphasis)
                ModelStatusText(choice: ModelChoice.current)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.fillSubtle))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border))
        .contentShape(Rectangle())
    }
}

/// "Ready on the Neural Engine", "Downloaded", "Not downloaded"… for a model.
struct ModelStatusText: View {
    @EnvironmentObject private var controller: DictationController
    let choice: ModelChoice

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(Theme.font(13))
                .monospacedDigit()
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
        }
    }

    private var isCurrent: Bool { choice == ModelChoice.current }
    private var isDownloaded: Bool { controller.downloadedModels.contains(choice) }

    private var text: String {
        if choice == .apple {
            return isCurrent ? "In use, built into iOS" : "Built into iOS"
        }
        if isCurrent {
            switch controller.modelState {
            case .ready:
                return controller.engine == .parakeetCPU ? "Loaded, on the CPU" : "Loaded on the Neural Engine"
            case .standby:
                return controller.isSessionLive ? "Downloaded" : "Downloaded. Loads when the engine turns on"
            case .loading:
                return "Loading onto your iPhone…"
            case let .downloading(progress, label):
                return "\(label), \(Int(progress * 100))%"
            case .failed:
                return isDownloaded ? "Downloaded, couldn't load" : "Download failed"
            case .notDownloaded:
                return isDownloaded ? "Downloaded" : "Not downloaded, \(choice.downloadMB) MB"
            }
        }
        return isDownloaded ? "Downloaded, \(choice.downloadMB) MB" : "Not downloaded, \(choice.downloadMB) MB"
    }

    private var color: Color {
        if isCurrent {
            switch controller.modelState {
            case .ready: return Theme.successFg
            case .loading, .downloading: return Theme.warningFg
            case .failed: return Theme.errorFg
            case .notDownloaded, .standby: break
            }
        }
        return isDownloaded ? Theme.textMuted : Theme.textFaint.opacity(0.6)
    }
}

/// The models: which one is in use, which are on the device, and the
/// controls to switch, download and delete. Shared by Settings and its own
/// page reached from Home.
struct ModelsSection: View {
    @EnvironmentObject private var controller: DictationController
    @State private var parakeetOnly = Settings.parakeetOnly

    var body: some View {
        Section {
            ForEach(ModelChoice.allCases) { choice in
                ModelRow(choice: choice)
            }
        } header: {
            SectionLabel(text: "Speech model")
                .padding(.top, 8)
                .padding(.bottom, 4)
        } footer: {
            Text("Tap a model to use it. Parakeet models are downloaded once from Hugging Face, pinned to an exact version, and after that Yapper works offline. Apple on-device is built into iOS: nothing to download, less accurate.")
                .padding(.top, 4)
        }

        if ModelChoice.current.isParakeet {
        Section {
            Toggle("Only use Parakeet", isOn: $parakeetOnly)
                .onChange(of: parakeetOnly) { _, value in Settings.parakeetOnly = value }
                // Choosing Apple turns it off behind this view's back.
                .onAppear { parakeetOnly = Settings.parakeetOnly }
        } footer: {
            Text(parakeetOnly
                 ? "Yapper never uses Apple's recognizer. If Parakeet isn't downloaded the engine won't turn on, and if it's still getting ready a dictation waits for it."
                 : "While no Parakeet model is ready, Apple's on-device recognizer fills in. History says which engine did each dictation, and why.")
                .padding(.top, 4)
        }
        }
    }
}

/// One model: tap to use it; download, progress and delete in place.
struct ModelRow: View {
    @EnvironmentObject private var controller: DictationController
    let choice: ModelChoice
    @State private var confirmDelete = false

    private var isCurrent: Bool { choice == ModelChoice.current }
    private var isDownloaded: Bool { controller.downloadedModels.contains(choice) }
    private var isDownloadingThis: Bool {
        if case .downloading = controller.modelState, isCurrent { return true }
        return false
    }
    private var anyDownload: Bool {
        if case .downloading = controller.modelState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isCurrent && isDownloaded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isCurrent && isDownloaded ? Theme.textEmphasis : Theme.textFaint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.title)
                        .font(Theme.font(16, .semibold))
                        .foregroundStyle(Theme.textEmphasis)
                    Text(choice.detail)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.textMuted)
                    ModelStatusText(choice: choice)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                if isDownloaded, choice.isParakeet {
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(isDownloadingThis)
                    .accessibilityLabel("Delete \(choice.title)")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard isDownloaded, !isCurrent else { return }
                Task { await controller.selectModel(choice) }
            }

            if isDownloadingThis, case let .downloading(progress, _) = controller.modelState {
                ProgressView(value: progress)
                    .tint(Theme.textEmphasis)
                    .padding(.leading, 34)
                Text("Keep Yapper open until it finishes.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.leading, 34)
            } else if !isDownloaded, choice.isParakeet {
                Button {
                    Task { await controller.downloadModel(choice) }
                } label: {
                    Label("Download \(choice.downloadMB) MB", systemImage: "arrow.down.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(anyDownload)
                .padding(.leading, 34)
            } else if isCurrent, case let .failed(message) = controller.modelState {
                Text(message)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.errorFg)
                    .padding(.leading, 34)
                Button("Try again") { Task { await controller.selectModel(choice) } }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 8)
        .confirmationDialog("Delete \(choice.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete \(choice.downloadMB) MB", role: .destructive) {
                Task { await controller.deleteModel(choice) }
            }
        } message: {
            Text(isCurrent
                 ? "This is the model in use. You can download it again any time."
                 : "You can download it again any time.")
        }
    }
}

/// The model list as its own page, reached from Home.
struct ModelsView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        Form {
            ModelsSection()
        }
        .font(Theme.font(16))
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Speech models")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { controller.refreshDownloadedModels() }
    }
}
