import SwiftUI

struct MainView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var tab = Tab.home

    enum Tab { case home, history, dictionary, settings }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "waveform") }
                .tag(Tab.home)
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock") }
                .tag(Tab.history)
            NavigationStack { DictionaryView() }
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
                .tag(Tab.dictionary)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // A hands-free dictation finished in the background: open on it.
        .onChange(of: controller.revealRecord) { _, id in
            if id != nil { tab = .history }
        }
    }
}

/// Home: one big power button for the speech engine, what it's doing in a
/// word, and nothing else. Everything else lives in Settings. Up top: help,
/// and Dictate, which records right here (the power button only gets the
/// keyboard ready).
struct HomeView: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardEnabled = KeyboardStatus.isEnabled
    @State private var firstLoadNote = false
    @State private var showSetup = false
    @State private var showHelp = false
    /// Help's "Add the Yapper keyboard": the setup opens once help is gone.
    @State private var setupAfterHelp = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                helpButton
                dictateButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 24)

            TimelineView(.animation(minimumInterval: 0.25, paused: controller.modelState != .loading)) { context in
                let status = status(at: context.date)
                VStack(spacing: 44) {
                    PowerButton(look: status.look, progress: status.progress, action: toggle)
                        .accessibilityLabel("Yapper")
                        .accessibilityValue(status.spoken)
                        .accessibilityHint(controller.isSessionLive ? "Turns the speech engine off" : "Turns the speech engine on")
                        .accessibilityIdentifier("home.power")
                    labels(status)
                }
            }

            Spacer(minLength: 24)

            if !keyboardEnabled {
                Button { showSetup = true } label: {
                    HStack(spacing: 4) {
                        Text("Finish setup: add the Yapper keyboard")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.textMuted)
                    .frame(minHeight: Theme.controlHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .firstLoadNote(isPresented: $firstLoadNote)
        .sheet(isPresented: $showHelp, onDismiss: {
            if setupAfterHelp {
                setupAfterHelp = false
                showSetup = true
            }
        }) {
            HomeHelpView(needsKeyboard: !keyboardEnabled) { setupAfterHelp = true }
        }
        .sheet(isPresented: $showSetup, onDismiss: { keyboardEnabled = KeyboardStatus.isEnabled }) {
            OnboardingView(start: .keyboard) { showSetup = false }
                .environmentObject(controller)
        }
        .onAppear { keyboardEnabled = KeyboardStatus.isEnabled }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { keyboardEnabled = KeyboardStatus.isEnabled }
        }
    }

    /// Dictating inside Yapper, copied when it's done: the Action Button's
    /// dictation, from Home.
    private var dictateButton: some View {
        Button {
            if controller.isSessionLive || controller.startSession() {
                controller.beginRecording(source: .app)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                Text("Dictate")
                    .font(Theme.font(15, .medium))
            }
            .foregroundStyle(Theme.textEmphasis)
            .padding(.horizontal, 16)
            .frame(height: Theme.controlHeight)
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dictate and copy")
        .accessibilityIdentifier("home.dictate")
    }

    private var helpButton: some View {
        Button { showHelp = true } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .frame(width: Theme.controlHeight, height: Theme.controlHeight)
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Yapper works")
        .accessibilityIdentifier("home.help")
    }

    private func labels(_ status: Status) -> some View {
        VStack(spacing: 6) {
            Text(status.title)
                .font(Theme.display(28))
                .tracking(-0.6)
                .foregroundStyle(Theme.textEmphasis)
                .accessibilityHidden(true)
            if let detail = status.detail {
                Text(detail)
                    .font(Theme.font(14))
                    .monospacedDigit()
                    .foregroundStyle(status.detailIsError ? Theme.errorFg : Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 300)
                    .accessibilityHidden(!status.detailIsError)
            }
            if let hint = status.hint {
                Text(hint)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        // Room for a detail and a hint, so the button doesn't move when they show.
        .frame(minHeight: 88, alignment: .top)
        .padding(.horizontal, 20)
    }

    private func toggle() {
        Haptics.toggle()
        if controller.switchEngine(on: !controller.isSessionLive) { firstLoadNote = true }
    }

    // MARK: State

    struct Status {
        var look: PowerButton.Look
        var progress: Double?
        var title: String
        var detail: String?
        var detailIsError = false
        /// What the power button is for, in a line: on gets the keyboard
        /// ready, it doesn't record.
        var hint: String?

        /// For VoiceOver: the title and, unless it's an error read on its
        /// own, the detail.
        var spoken: String {
            guard let detail, !detailIsError else { return title }
            return "\(title), \(detail)"
        }
    }

    private func status(at now: Date) -> Status {
        if let pinned = Self.pinnedStatus { return pinned }
        let error = controller.errorMessage
        switch controller.phase {
        case .idle:
            if controller.interrupted {
                return Status(look: .paused, title: "Paused",
                              detail: error ?? "A call took the microphone. Tap to resume.", detailIsError: error != nil)
            }
            return Status(look: .off, title: "Off", detail: error, detailIsError: error != nil, hint: Self.offHint)
        case .recording:
            return Status(look: .lit(Theme.recording), title: "Listening")
        case .transcribing:
            return Status(look: .lit(Theme.working), title: "Typing")
        case .ready, .preparing:
            break
        }
        if controller.modelState == .loading {
            let (progress, detail) = loading(at: now)
            // With Don't wait for Parakeet, Apple on-device already takes
            // dictations, so the engine is on while Parakeet loads.
            if Settings.appleWhileLoading, !Settings.parakeetOnly {
                return Status(look: .lit(Theme.ready), progress: progress, title: "On", detail: detail, hint: Self.onHint)
            }
            return Status(look: .off, progress: progress, title: "Starting", detail: detail)
        }
        let until = controller.sessionEnds.map { "Until \($0.formatted(date: .omitted, time: .shortened))" }
        return Status(look: .lit(Theme.ready), title: "On", detail: until, hint: Self.onHint)
    }

    private static let onHint = "Ready: tap the mic in the Yapper keyboard"
    private static let offHint = "Turn on to dictate from the keyboard"


    /// The ring and "Loading… 40%": measured from last load's timings when
    /// there are any, otherwise step by step.
    private func loading(at now: Date) -> (Double, String) {
        guard let stage = controller.loadStage else { return (0.02, "Loading…") }
        if let timed = LoadProgress.timedProgress(stage: stage, stageStarted: controller.loadStageStarted,
                                                  estimate: controller.loadEstimate, at: now) {
            return (timed.fraction, "Loading… \(Int(timed.fraction * 100))%")
        }
        let detail = stage.step > 0 ? "Loading… step \(stage.step) of \(stage.total)" : "Loading…"
        return (LoadProgress.stepFraction(stage), detail)
    }

    /// `-homeState off|on|loading|paused`: the screenshot tests show a state
    /// without a microphone or a model (simulator only, with `-screenshots`).
    private static let pinnedStatus: Status? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-screenshots"), let index = arguments.firstIndex(of: "-homeState"),
              arguments.indices.contains(index + 1) else { return nil }
        // 15 minutes after the 9:41 the screenshots' status bar shows.
        let ends = Calendar.current.date(bySettingHour: 9, minute: 56, second: 0, of: Date()) ?? Date()
        let until = ends.formatted(date: .omitted, time: .shortened)
        switch arguments[index + 1] {
        case "on": return Status(look: .lit(Theme.ready), title: "On", detail: "Until \(until)", hint: Self.onHint)
        case "loading": return Status(look: .off, progress: 0.4, title: "Starting", detail: "Loading… 40%")
        case "paused": return Status(look: .paused, title: "Paused", detail: "A call took the microphone. Tap to resume.")
        default: return Status(look: .off, title: "Off", hint: Self.offHint)
        }
    }()
}

/// Whether the Yapper keyboard has been added in Settings.
enum KeyboardStatus {
    static let bundleID = "com.gluska.yapper.keyboard"

    /// Known once the keyboard has appeared with Full Access (it records
    /// that in the App Group). There's no public API to ask iOS directly.
    /// `-keyboardAdded` (screenshot tests only, with `-screenshots`) shows
    /// Home as it is once set up.
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-screenshots"), arguments.contains("-keyboardAdded") { return true }
        return Bridge.defaults.bool(forKey: Bridge.Key.keyboardSeen)
    }

    static var hasFullAccess: Bool {
        Bridge.defaults.bool(forKey: Bridge.Key.fullAccessSeen)
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
