import AVFoundation
import SwiftUI

/// One screen per step. Progress is saved, so leaving for iOS Settings and
/// coming back (even if iOS closed Yapper meanwhile) resumes where you were.
/// Nothing here blocks: every step can be skipped and done later.
struct OnboardingView: View {
    let onFinish: () -> Void

    enum Step: Int, CaseIterable {
        // The model comes early: if the user wants Parakeet, it downloads while
        // they add the keyboard.
        case welcome, microphone, model, keyboard, fullAccess, tryIt
    }

    @EnvironmentObject private var controller: DictationController
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: Step
    @State private var micStatus = Recorder.permission
    @State private var keyboardAdded = KeyboardStatus.isEnabled
    @State private var fullAccess = KeyboardStatus.hasFullAccess
    @State private var practice = ""
    @FocusState private var practiceFocused: Bool

    private static let stepKey = "onboarding.step"

    /// `start`: a step to open on, for finishing setup later from Home.
    init(start: Step? = nil, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: start ?? Self.savedStep)
    }

    private static var savedStep: Step {
        // `-onboardingStep <name>`: the screenshot tests open a given step.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-onboardingStep"), arguments.indices.contains(index + 1),
           let step = Step.allCases.first(where: { "\($0)" == arguments[index + 1] }) {
            return step
        }
        return Step(rawValue: Bridge.defaults.integer(forKey: stepKey)) ?? .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, 20)
                .padding(.top, 12)
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            if step != .model {
                DownloadBanner()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            footer
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .background(Theme.background)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshStatus() }
        }
        // The keyboard reports Full Access when it appears; check while the
        // user tries it on the Full Access and Try steps.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if step == .fullAccess || step == .keyboard || step == .tryIt { refreshStatus() }
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.textEmphasis : Theme.fillActive)
                    .frame(height: 4)
            }
        }
    }

    // MARK: Buttons

    /// Each step's buttons, pinned under it: one big main button, and room
    /// under it for a second choice even when there isn't one, so the main
    /// button sits in the same spot on every step.
    private var footer: some View {
        let actions = self.actions
        return VStack(spacing: 4) {
            Button(actions.main.title, action: actions.main.run)
                .buttonStyle(PrimaryButtonStyle(large: true))
            Group {
                if let other = actions.other {
                    Button(other.title, action: other.run)
                        .buttonStyle(TextButtonStyle())
                } else {
                    Color.clear
                }
            }
            .frame(height: Theme.controlHeight)
        }
    }

    private struct Action {
        let title: String
        let run: () -> Void
    }

    private var actions: (main: Action, other: Action?) {
        switch step {
        case .welcome:
            return (Action(title: "Get started") { go(to: .microphone) }, nil)
        case .microphone:
            switch micStatus {
            case .granted:
                return (Action(title: "Continue") { go(to: .model) }, nil)
            case .denied:
                return (Action(title: "Open Settings") { KeyboardStatus.openSettings() },
                        Action(title: "Skip for now") { go(to: .model) })
            default:
                // App Review wants a neutral label before the system prompt.
                return (Action(title: "Continue") {
                    Task {
                        _ = await Recorder.requestPermission()
                        // Apple's recognizer covers dictation until Parakeet
                        // is downloaded; it needs its own permission.
                        _ = await AppleSpeech.requestPermission()
                        micStatus = Recorder.permission
                        if micStatus == .granted { go(to: .model) }
                    }
                }, nil)
            }
        case .model:
            if controller.downloadedModels.contains(.ultra) {
                return (Action(title: "Continue") { go(to: .keyboard) }, nil)
            }
            let useApple = Action(title: controller.appleModel == .notInstalled ? "Use Apple's model (get the newest)" : "Use Apple's model") {
                // iOS 26 without Apple's newest model for this language:
                // ask iOS to fetch it. Until then the older one works.
                if controller.appleModel == .notInstalled {
                    Task { await controller.installAppleModel() }
                }
                go(to: .keyboard)
            }
            return (useApple, Action(title: "Download Parakeet, \(ModelChoice.ultra.downloadMB) MB") {
                Task { await controller.downloadModel(.ultra) }
                go(to: .keyboard)
            })
        case .keyboard:
            if keyboardAdded {
                return (Action(title: "Continue") { go(to: .fullAccess) }, nil)
            }
            return (Action(title: "Open Settings") { KeyboardStatus.openSettings() },
                    Action(title: "I've added it") { go(to: .fullAccess) })
        case .fullAccess:
            if fullAccess {
                return (Action(title: "Continue") { go(to: .tryIt) }, nil)
            }
            return (Action(title: "Open Settings") { KeyboardStatus.openSettings() },
                    Action(title: "Skip for now") { go(to: .tryIt) })
        case .tryIt:
            return (Action(title: "Done") { finish() }, nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .microphone: microphone
        case .keyboard: keyboard
        case .fullAccess: fullAccessStep
        case .model: model
        case .tryIt: tryIt
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 40)
            PageTitle(title: "Talk. It types.", subtitle: "Yapper turns your voice into text in any app.")
            VStack(alignment: .leading, spacing: 16) {
                Point(title: "Private", text: "Speech is turned into text on your iPhone. Audio and text never leave it.")
                Point(title: "Free, no limits", text: "No subscription, no word cap, no account.")
                Point(title: "No tracking", text: "No analytics, no ads, nothing sent anywhere.")
                Point(title: "Open source", text: "Every line is public, so anyone can check.")
            }
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Microphone",
                      subtitle: "Yapper listens only while you dictate. The audio is turned into text on this iPhone and never leaves it.")
            switch micStatus {
            case .granted:
                Done(text: "Microphone is on")
            case .denied:
                Text("Microphone access is off. Turn it on in Settings, under Yapper, then Microphone.")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.text)
            default:
                EmptyView()
            }
        }
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Add the keyboard", subtitle: "The Yapper keyboard is how your voice gets into other apps.")
            Card {
                NumberedStep(number: 1, text: "Tap Open Settings below")
                Hairline()
                NumberedStep(number: 2, text: "Tap **Keyboards**")
                Hairline()
                NumberedStep(number: 3, text: "Turn on **Yapper**")
            }
            if keyboardAdded {
                Done(text: "Yapper keyboard added")
            }
        }
    }

    private var fullAccessStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Allow Full Access", subtitle: "Same place in Settings: Keyboards, then Yapper, then Allow Full Access.")
            Text("iOS keyboards can't use the microphone, so the Yapper keyboard asks the Yapper app to listen, and the two pass your text through a private folder on this iPhone. Full Access is what lets them do that. The warning iOS shows is generic: the Yapper keyboard has no internet code at all, and the source is public.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
            if fullAccess {
                Done(text: "Full Access is on")
            } else {
                Text("To check, tap the box below and switch to the Yapper keyboard with the globe key.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textMuted)
                PracticeField(text: $practice, focused: $practiceFocused, placeholder: "Tap here to check")
            }
        }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Speech model", subtitle: "You can change it any time in Settings.")
            Text("Yapper uses Apple's on-device speech model, and it's the one we recommend. It's built into iOS, so there's nothing to download and it starts instantly. Like everything in Yapper, it runs on this iPhone and nothing is sent anywhere.")
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
            Text("Optional: Yapper also supports Parakeet, a speech model from NVIDIA that runs on your iPhone's Neural Engine and can be more accurate. It's a one-time \(ModelChoice.ultra.downloadMB) MB download (Wi-Fi is a good idea) and takes a few seconds to start each time you turn Yapper on. It keeps downloading while you finish setting up, and Apple's model fills in until it's ready.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
            Card {
                SectionLabel(text: "Good to know")
                GoodToKnowList(compact: true)
                Text("More in Settings › About › Good to know.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textFaint)
            }
            if controller.downloadedModels.contains(.ultra) {
                Done(text: "Parakeet is downloaded")
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Try it", subtitle: "Tap the box, switch to the Yapper keyboard with the globe key, then tap anywhere on it.")
            PracticeField(text: $practice, focused: $practiceFocused, placeholder: "Say something…")
            Text("In other apps, the first dictation opens Yapper to start listening, and Yapper takes you back to your app by itself. If it can't, swipe right along the bottom edge of the screen. Your words will be there.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
            Text("After that the mic stays ready for \(Settings.sessionLabel), so the keyboard records right where you are.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func refreshStatus() {
        keyboardAdded = KeyboardStatus.isEnabled
        fullAccess = KeyboardStatus.hasFullAccess
        micStatus = Recorder.permission
    }

    private func go(to next: Step) {
        practiceFocused = false
        Bridge.defaults.set(next.rawValue, forKey: Self.stepKey)
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func finish() {
        Bridge.defaults.removeObject(forKey: Self.stepKey)
        onFinish()
    }
}

/// A second choice under the main button: plain text, full width.
private struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .medium))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private struct Point: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.font(16, .semibold)).foregroundStyle(Theme.textEmphasis)
            Text(text).font(Theme.font(14)).foregroundStyle(Theme.textMuted)
        }
    }
}

/// A plain checkmark line for a finished step.
private struct Done: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(Theme.font(15, .medium))
            .foregroundStyle(Theme.successFg)
    }
}

private struct PracticeField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .focused(focused)
            .font(Theme.font(17))
            .lineLimit(3...8)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.panelRadius).fill(Theme.fillInput))
            .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius).strokeBorder(Theme.borderInput))
    }
}

/// A numbered step: onboarding's way into Settings, and Home's help.
struct NumberedStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(Theme.font(13, .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.fillActive))
                .foregroundStyle(Theme.textEmphasis)
            Text(text)
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The model download's progress, pinned under the onboarding steps.
private struct DownloadBanner: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        switch controller.modelState {
        case let .downloading(progress, label):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Parakeet: \(label.lowercased())")
                    Spacer()
                    Text("\(Int(progress * 100))%").monospacedDigit()
                }
                .font(Theme.font(13, .medium))
                .foregroundStyle(Theme.textMuted)
                ProgressView(value: progress).tint(Theme.textEmphasis)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.fillSubtle))
        case .failed where Settings.wantsModelDownload:
            Text("Parakeet's download paused. It picks up again when you come back to Yapper.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textMuted)
        default:
            EmptyView()
        }
    }
}
