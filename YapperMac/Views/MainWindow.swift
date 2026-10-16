import AppKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case setup
    case model
    case settings
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "Get started"
        case .model: return "Speech model"
        case .settings: return "Settings"
        case .history: return "History"
        }
    }

    var symbol: String {
        switch self {
        case .setup: return "checklist"
        case .model: return "cpu"
        case .settings: return "slider.horizontal.3"
        case .history: return "clock"
        }
    }
}

/// Yapper's one window. Yapper is a menu bar app with no Dock icon; while
/// this window is open it gets one, so it can be found with ⌘-Tab.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    final class Selection: ObservableObject {
        @Published var pane: Pane = .setup
    }

    private var window: NSWindow?
    private let selection = Selection()

    func show(_ pane: Pane? = nil) {
        if let pane { selection.pane = pane }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let root = MainWindow()
            .environmentObject(MacDictation.shared)
            .environmentObject(selection)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Yapper"
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 680, height: 480)
        window.contentViewController = NSHostingController(rootView: root)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("YapperMain")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MainWindow: View {
    @EnvironmentObject private var selection: MainWindowController.Selection
    @EnvironmentObject private var dictation: MacDictation

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: Binding(get: { selection.pane }, set: { if let pane = $0 { selection.pane = pane } })) { pane in
                Label {
                    Text(pane.title).font(Theme.font(13, .medium))
                } icon: {
                    Image(systemName: pane.symbol)
                }
                .badge(pane == .setup && !dictation.isSetUp ? Text("!") : nil)
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch selection.pane {
                case .setup: SetupPane()
                case .model: ModelPane()
                case .settings: SettingsPane()
                case .history: HistoryPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
        .onAppear { dictation.refreshPermissions() }
    }
}

// MARK: - Building blocks

/// A scrolling page with Yapper's title style.
struct PaneScroll<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(title: title, subtitle: subtitle)
                content
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One line in a card: what it is, a note under it, and a control.
struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.textEmphasis)
                if let detail {
                    Text(detail)
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Small rounded status label: "Allowed", "Needed".
struct StatusTag: View {
    enum Tone { case good, bad, neutral, working }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(Theme.font(11, .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch tone {
        case .good: return Theme.successFg
        case .bad: return Theme.errorFg
        case .neutral: return Theme.textMuted
        case .working: return Theme.warningFg
        }
    }

    private var background: Color {
        switch tone {
        case .good: return Theme.successBg
        case .bad: return Theme.errorBg
        case .neutral: return Theme.fillInput
        case .working: return Theme.warningBg
        }
    }
}

/// A compact button in Yapper's style, sized for a Mac.
struct SmallButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(12, .semibold))
                .foregroundStyle(primary ? Theme.onPrimary : Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(primary ? Theme.primary : Theme.fillInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(primary ? Color.clear : Theme.borderInput, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
