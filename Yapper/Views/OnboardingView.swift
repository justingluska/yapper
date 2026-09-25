import AVFoundation
import SwiftUI

/// One screen per step. Progress is saved, so leaving for iOS Settings and
/// coming back (even if iOS closed Yapper meanwhile) resumes where you were.
/// Nothing here blocks: every step can be skipped and done later.
struct OnboardingView: View {
    let onFinish: () -> Void

    enum Step: Int, CaseIterable {
        // The model comes early: if the user wants it, it downloads while
        // they add the keyboard.
        case welcome, microphone, model, keyboard, fullAccess, tryIt
    }

    @EnvironmentObject private var controller: DictationController
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: Step = OnboardingView.savedStep
    @State private var micStatus = Recorder.permission
    @State private var keyboardAdded = KeyboardStatus.isEnabled
    @State private var fullAccess = KeyboardStatus.hasFullAccess
    @State private var practice = ""
    @FocusState private var practiceFocused: Bool

    private static let stepKey = "onboarding.step"

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
            Button("Get started") { go(to: .microphone) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Microphone",
                      subtitle: "Yapper listens only while you dictate. The audio is turned into text on this iPhone and never leaves it.")
            switch micStatus {
            case .granted:
                Done(text: "Microphone is on")
                Button("Continue") { go(to: .model) }
                    .buttonStyle(PrimaryButtonStyle())
            case .denied:
                Text("Microphone access is off. Turn it on in Settings, under Yapper, then Microphone.")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.text)
                Button("Open Settings") { KeyboardStatus.openSettings() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Skip for now") { go(to: .model) }
                    .buttonStyle(SecondaryButtonStyle())
            default:
                // App Review wants a neutral label before the system prompt.
                Button("Continue") {
                    Task {
                        _ = await Recorder.requestPermission()
                        // Apple's recognizer covers dictation until Parakeet
                        // is downloaded; it needs its own permission.
                        _ = await AppleSpeech.requestPermission()
                        micStatus = Recorder.permission
                        if micStatus == .granted { go(to: .model) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Add the keyboard", subtitle: "The Yapper keyboard is how your voice gets into other apps.")
            Card {
                SettingsStep(number: 1, text: "Tap Open Settings below")
                Hairline()
                SettingsStep(number: 2, text: "Tap **Keyboards**")
                Hairline()
                SettingsStep(number: 3, text: "Turn on **Yapper**")
            }
            if keyboardAdded {
                Done(text: "Yapper keyboard added")
                Button("Continue") { go(to: .fullAccess) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Open Settings") { KeyboardStatus.openSettings() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("I've added it") { go(to: .fullAccess) }
                    .buttonStyle(SecondaryButtonStyle())
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
                Button("Continue") { go(to: .tryIt) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Open Settings") { KeyboardStatus.openSettings() }
                    .buttonStyle(PrimaryButtonStyle())
                Text("To check, tap the box below and switch to the Yapper keyboard with the globe key.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.textMuted)
                PracticeField(text: $practice, focused: $practiceFocused, placeholder: "Tap here to check")
                Button("Skip for now") { go(to: .tryIt) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Speech model", subtitle: "Optional. You can do it any time from Settings.")
            Text("Yapper works best with Parakeet, a speech model from NVIDIA that runs on your iPhone's Neural Engine. It's a one-time \(ModelChoice.ultra.downloadMB) MB download, so Wi-Fi is a good idea.")
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
            Text("If you download it, it keeps going while you finish setting up. If you leave Yapper for a moment (to add the keyboard), it picks up again when you come back. Until it's done, Apple's speech recognizer does the work, also on this iPhone.")
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
                Button("Continue") { go(to: .keyboard) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Download \(ModelChoice.ultra.downloadMB) MB and continue") {
                    Task { await controller.downloadModel(.ultra) }
                    go(to: .keyboard)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Not now") { go(to: .keyboard) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageTitle(title: "Try it", subtitle: "Tap the box, switch to the Yapper keyboard with the globe key, then tap anywhere on it.")
            PracticeField(text: $practice, focused: $practiceFocused, placeholder: "Say something…")
            Text("The first time, the keyboard opens Yapper, which starts listening right away. Talk, tap to finish, then swipe right along the bottom edge of the screen to go back. Your words will be there.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
            Text("After that the mic stays ready for \(sessionLabel), so the keyboard records right where you are.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
            Button("Done") { finish() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var sessionLabel: String {
        let minutes = Settings.sessionMinutes
        return minutes == 0 ? "until you turn it off" : minutes >= 60 ? "an hour" : "\(minutes) minutes"
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

private struct SettingsStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(Theme.font(13, .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.fillActive))
                .foregroundStyle(Theme.textEmphasis)
            Text(text)
                .font(Theme.font(15))
                .foregroundStyle(Theme.text)
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
