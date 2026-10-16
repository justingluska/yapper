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
        EngineHook.turnOn = { try DictationController.shared.turnOnInBackground() }
        if ProcessInfo.processInfo.arguments.contains("-screenshots") { Self.seedScreenshotData() }
    }

    /// Sample History and stats for the screenshot tests (simulator only;
    /// `-screenshots` is never passed on a phone). History is written fresh on
    /// every launch, so each test sees its own sample; stats only once.
    /// `-sampleHistory` adds older dictations, a long one and recordings, for
    /// the History tools.
    private static func seedScreenshotData() {
        let firstRun = HistoryStore.load().isEmpty
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
                duration: Double(text.count) / 14, engine: Engine.appleAnalyzer.rawValue,
                model: "Apple on-device", processingTime: 0.21))
        }
        if ProcessInfo.processInfo.arguments.contains("-sampleHistory") {
            let older: [(days: Double, text: String, recording: Bool)] = [
                (1, "Okay, so here's the plan for Saturday. We meet at the trailhead at eight, not seven thirty, because the parking lot doesn't open until quarter to. Bring two liters of water each, more if it's hot, and something salty for the top. The loop is about eleven miles with the long climb in the first three, so we'll take it slow and stop at the creek crossing for a snack. If it rains on Friday night the lower trail turns to mud, and in that case we'll do the ridge route instead, which is shorter but steeper. I'll text everyone by nine on Friday either way. Sam is driving the second car and can take four people plus packs. After the hike there's that taco place near the gas station that opens at two, and I already called ahead for a table for eight. If anyone needs to bail, just tell me by Thursday so I can fix the reservation. Last thing: wear real boots, not running shoes, the descent is loose gravel the whole way down.", true),
                (2, "Note to self: the plumber said Tuesday between ten and two, and to leave the side gate open.", true),
                (2.4, "Pick up oat milk, coffee filters, lemons and a birthday card for Dana.", true),
                (5, "Thanks for the intro. I'd love to grab coffee next week if you have time.", false),
                (9, "The quarterly numbers look good, but let's double-check the churn figure before we send it.", false),
                (20, "Book the dentist for the first week of next month, mornings only.", false),
            ]
            // Two seconds of a quiet tone at the iPhone microphone's usual rate.
            let tone = (0..<96_000).map { Float(sin(Double($0) * 2 * .pi * 220 / 48_000) * 0.05) }
            for item in older {
                let id = UUID()
                records.append(DictationRecord(
                    id: id, date: Date().addingTimeInterval(-item.days * 86_400), text: item.text, raw: item.text,
                    duration: Double(item.text.count) / 14, engine: Engine.appleAnalyzer.rawValue,
                    model: "Apple on-device", processingTime: 0.34,
                    audioFile: item.recording ? RecordingStore.save(tone, sampleRate: 48_000, id: id) : nil))
            }
        }
        HistoryStore.save(records)
        RecordingStore.prune()
        guard firstRun else { return }
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
                    // Exports left behind if Yapper closed mid-share.
                    HistoryTransfer.cleanUpAll()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                controller.handleStartRequest()
                // Keep recordings can be as short as an hour.
                if RecordingStore.prune() { controller.historyChanged() }
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
        AppShortcut(
            intent: TurnOnEngineIntent(),
            phrases: ["Turn on \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Turn On Yapper",
            systemImageName: "waveform"
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
