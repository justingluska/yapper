import AppKit
import SwiftUI

/// The small pill at the bottom of the screen while Yapper listens or
/// transcribes. It floats over everything, in every Space and full-screen
/// app, and never takes focus or clicks from the app you're typing in.
@MainActor
final class HUDController {
    static let shared = HUDController()

    final class Model: ObservableObject {
        enum Content: Equatable {
            case listening(handsFree: Bool)
            case transcribing
            case message(String, isError: Bool)
        }

        @Published var content: Content = .transcribing
        /// The last few levels, oldest first, for the waveform.
        @Published var levels: [Float] = Array(repeating: 0, count: HUDView.barCount)
    }

    let model = Model()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func showListening(handsFree: Bool) {
        model.levels = Array(repeating: 0, count: HUDView.barCount)
        show(.listening(handsFree: handsFree))
    }

    func showTranscribing() {
        show(.transcribing)
    }

    /// A short note that hides itself.
    func showMessage(_ text: String, isError: Bool = false, seconds: Double = 2.5) {
        show(.message(text, isError: isError))
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func push(level: Float) {
        var levels = model.levels
        levels.removeFirst()
        levels.append(level)
        model.levels = levels
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private func show(_ content: Model.Content) {
        hideWork?.cancel()
        hideWork = nil
        model.content = content
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: HUDView.width, height: HUDView.height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host
        return panel
    }

    /// Bottom center of the screen the pointer is on, above the Dock.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.midX - HUDView.width / 2, y: area.minY + 28))
    }
}

struct HUDView: View {
    static let width: CGFloat = 320
    static let height: CGFloat = 44
    static let barCount = 18

    @ObservedObject var model: HUDController.Model

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            pill
            Spacer(minLength: 0)
        }
        .frame(width: Self.width, height: Self.height)
    }

    private var pill: some View {
        HStack(spacing: 10) {
            switch model.content {
            case let .listening(handsFree):
                Circle().fill(Theme.Island.recording).frame(width: 8, height: 8)
                waveform
                if handsFree {
                    Text("esc to cancel")
                        .font(Theme.font(11, .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Island.working)
                Text("Transcribing")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(.white.opacity(0.85))
            case let .message(text, isError):
                Text(text)
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(isError ? Theme.Island.recording : .white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(Color.black.opacity(0.88)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2, height: 3 + CGFloat(level) * 15)
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: model.levels)
    }
}
