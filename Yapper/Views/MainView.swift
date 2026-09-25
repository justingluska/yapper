import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "waveform") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock") }
            NavigationStack { DictionaryView() }
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var tryText = ""
    @State private var records = HistoryStore.load()
    @State private var keyboardEnabled = KeyboardStatus.isEnabled
    @FocusState private var tryFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    PageTitle(title: "Yapper", subtitle: "Free, private dictation. Nothing leaves your iPhone.")
                }

                if !keyboardEnabled {
                    Card {
                        Text("Add the Yapper keyboard to dictate into any app: Settings, Keyboards, then turn on Yapper and Allow Full Access.")
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.text)
                        Button("Open Settings") { KeyboardStatus.openSettings() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }

                SpeechEngineCard()

                Card {
                    HStack {
                        SectionLabel(text: "Try it")
                        if tryFocused {
                            Button("Done") { tryFocused = false }
                                .font(Theme.font(14, .semibold))
                                .foregroundStyle(Theme.textEmphasis)
                        }
                    }
                    TextField("Tap here, switch to the Yapper keyboard, and tap it", text: $tryText, axis: .vertical)
                        .font(Theme.font(16))
                        .lineLimit(3...8)
                        .focused($tryFocused)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.fillInput))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderInput))
                    if !tryText.isEmpty {
                        Button("Clear") { tryText = "" }
                            .font(Theme.font(14, .medium))
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                if !records.isEmpty {
                    Text("\(records.filter { !$0.failed }.count) dictations, \(wordCount) words so far")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(20)
        }
        // A dictation keyboard has no dismiss key, so dragging the page (or
        // Done) puts it away.
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            records = HistoryStore.load()
            keyboardEnabled = KeyboardStatus.isEnabled
        }
        .onChange(of: controller.historyVersion) { _, _ in records = HistoryStore.load() }
    }

    private var wordCount: Int {
        records.reduce(0) { $0 + $1.wordCount }
    }
}

/// Whether the Yapper keyboard has been added in Settings.
enum KeyboardStatus {
    static let bundleID = "com.gluska.yapper.keyboard"

    /// Known once the keyboard has appeared with Full Access (it records
    /// that in the App Group). There's no public API to ask iOS directly.
    static var isEnabled: Bool {
        Bridge.defaults.bool(forKey: Bridge.Key.keyboardSeen)
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
