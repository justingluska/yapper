import SwiftUI
import UIKit

/// The input view adopts UIInputViewAudioFeedback so key clicks follow the
/// user's system "Keyboard Clicks" setting.
final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel!
    private var host: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

    override func loadView() {
        let view = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        view.allowsSelfSizing = true
        self.inputView = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model = KeyboardModel(controller: self)
        let host = UIHostingController(rootView: KeyboardRootView(model: model))
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host

        // One fixed height, set once. Changing it later makes iOS 26 flicker.
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.height(compact: isCompactHeight))
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.appear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.disappear()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let compact = size.width > size.height
        heightConstraint?.constant = KeyboardMetrics.height(compact: compact)
        model.compact = compact
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.textDidChange()
    }

    private var isCompactHeight: Bool {
        let bounds = UIScreen.main.bounds
        return bounds.width > bounds.height
    }

    // MARK: Opening the app

    /// Keyboards can't call UIApplication.open. Try the extension context
    /// first, then SwiftUI's openURL (which the root view hands us).
    var swiftUIOpen: ((URL) -> Void)?

    func openApp(_ url: URL) {
        guard let context = extensionContext else {
            swiftUIOpen?(url)
            return
        }
        context.open(url) { [weak self] opened in
            guard !opened else { return }
            DispatchQueue.main.async { self?.swiftUIOpen?(url) }
        }
    }
}

enum KeyboardMetrics {
    /// About the height of the system keyboard, so the app's layout doesn't
    /// jump when switching between the two. The same for both modes, voice
    /// and typing: changing it later makes iOS flicker.
    static func height(compact: Bool) -> CGFloat { compact ? 190 : 260 }

    /// The typing layout's keys.
    static let keyGap: CGFloat = 6
    static func rowGap(compact: Bool) -> CGFloat { compact ? 5 : 10 }
    static func keyHeight(compact: Bool) -> CGFloat { compact ? 31 : 42 }
}
