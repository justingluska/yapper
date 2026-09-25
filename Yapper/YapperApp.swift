import ActivityKit
import AppIntents
import SwiftUI

@main
struct YapperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = DictationController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Transcriber.configure()
        YapperShortcuts.updateAppShortcutParameters()
        if ProcessInfo.processInfo.arguments.contains("-screenshots") { Self.seedScreenshotData() }
    }

    /// Sample History and stats for the screenshot tests (simulator only;
    /// `-screenshots` is never passed on a phone).
    private static func seedScreenshotData() {
        guard HistoryStore.load().isEmpty else { return }
        let calendar = Calendar.current
        var records: [DictationRecord] = []
        let samples = [
            "Sounds good, see you at six. I'll bring the wine.",
            "Can you send me the deck before the call tomorrow? I want to go over the pricing slide.",
            "Remind me to renew the car registration next week.",
        ]
        for (index, text) in samples.enumerated() {
            records.append(DictationRecord(
                date: Date().addingTimeInterval(-Double(index) * 5_400), text: text, raw: text,
                duration: Double(text.count) / 14, engine: Engine.parakeetNeuralEngine.rawValue,
                model: "Parakeet Ultra", processingTime: 0.21))
        }
        records.insert(DictationRecord(
            date: Date().addingTimeInterval(-1_800), text: "", raw: "", duration: 4.2,
            engine: Engine.parakeetNeuralEngine.rawValue, model: "Parakeet Ultra",
            error: "Parakeet Ultra was still loading. Only use Parakeet is on, so Yapper didn't use Apple's recognizer."), at: 1)
        HistoryStore.save(records)
        for day in 0..<120 where (day * 7) % 5 != 0 {
            guard let date = calendar.date(byAdding: .day, value: -day, to: Date()) else { continue }
            StatsStore.record(words: 40 + (day * 37) % 400, seconds: Double(20 + (day * 13) % 160), on: date)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .onOpenURL { url in
                    guard url.scheme == Bridge.urlScheme else { return }
                    if url.host == "dictate" {
                        controller.handleStartRequest()
                    }
                }
                .task {
                    controller.refreshModelState()
                    controller.resumeDownloadIfWanted()
                    RecordingStore.prune()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                controller.handleStartRequest()
                controller.refreshModelState()
                controller.resumeDownloadIfWanted()
                if controller.isSessionLive {
                    Task {
                        await controller.loadModelIfDownloaded()
                        await controller.restoreNeuralEngine()
                    }
                }
            } else if phase == .background, controller.phase != .recording, controller.phase != .transcribing {
                // The user swiped back to the keyboard; don't greet them with
                // a stale listening screen next time they open Yapper.
                controller.markReturned()
            }
        }
    }
}

struct YapperShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: ["Start dictating with \(.applicationName)", "Yap with \(.applicationName)"],
            shortTitle: "Start Dictating",
            systemImageName: "mic.fill"
        )
    }
}

struct RootView: View {
    @EnvironmentObject private var controller: DictationController
    /// `-screenshots` (the YapperScreens UI tests) skips onboarding without
    /// saving anything; `-dark` forces dark mode for them.
    @State private var onboarded = (Settings.onboarded || ProcessInfo.processInfo.arguments.contains("-screenshots"))
        && !ProcessInfo.processInfo.arguments.contains("-onboarding")
    private let forcedScheme: ColorScheme? = ProcessInfo.processInfo.arguments.contains("-dark") ? .dark : nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if onboarded {
                MainView()
            } else {
                OnboardingView {
                    Settings.onboarded = true
                    withAnimation { onboarded = true }
                }
            }
        }
        // Recording started from the keyboard or the Action Button: take
        // over the screen so the user knows what's happening.
        .fullScreenCover(isPresented: Binding(
            get: { controller.presentingListening },
            set: { if !$0 { controller.markReturned() } }
        )) {
            ListeningView()
                .environmentObject(controller)
        }
        .tint(Theme.textEmphasis)
        .preferredColorScheme(forcedScheme)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        Bridge.phase = .idle
        Bridge.post(.stateChanged)
        // Otherwise the Live Activity outlives a force-quit for hours. The
        // process is about to die, so wait (briefly) for the end to land.
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in Activity<SessionAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }
}
