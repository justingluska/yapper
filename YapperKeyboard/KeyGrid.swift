import SwiftUI

/// The typing layout: a plain QWERTY with numbers, symbols, shift, delete
/// with repeat, space, return and the globe. No autocorrect. It works without
/// Full Access (dictation needs Full Access; typing never does).
struct KeyGrid: View {
    @ObservedObject var model: KeyboardModel

    private static let letters: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    private static let numbers: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]
    private static let symbols: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    private var rows: [[String]] {
        switch model.layer {
        case .letters: return Self.letters
        case .numbers: return Self.numbers
        case .symbols: return Self.symbols
        }
    }

    var body: some View {
        GeometryReader { geo in
            let gap = KeyboardMetrics.keyGap
            let unit = (geo.size.width - 6 - gap * 9) / 10
            let height = KeyboardMetrics.keyHeight(compact: model.compact)

            VStack(spacing: KeyboardMetrics.rowGap(compact: model.compact)) {
                row(rows[0], unit: unit, height: height)
                row(rows[1], unit: unit, height: height)
                HStack(spacing: gap) {
                    thirdRowLeading(unit: unit, height: height)
                    Spacer(minLength: 0)
                    HStack(spacing: gap) {
                        ForEach(rows[2], id: \.self) { key in
                            CharacterKey(label: display(key), width: thirdRowKeyWidth(unit: unit), height: height) {
                                model.type(key)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    DeleteKey(model: model, width: unit * 1.35, height: height)
                }
                bottomRow(unit: unit, height: height)
            }
            .padding(.horizontal, 3)
        }
    }

    private func display(_ key: String) -> String {
        model.layer == .letters && model.shift != .off ? key.uppercased() : key
    }

    private func thirdRowKeyWidth(unit: CGFloat) -> CGFloat {
        // Letters row 3 keeps letter width; the 5 punctuation keys widen.
        model.layer == .letters ? unit : unit * 1.4
    }

    private func row(_ keys: [String], unit: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: KeyboardMetrics.keyGap) {
            ForEach(keys, id: \.self) { key in
                CharacterKey(label: display(key), width: unit, height: height) { model.type(key) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func thirdRowLeading(unit: CGFloat, height: CGFloat) -> some View {
        switch model.layer {
        case .letters:
            ShiftKey(model: model, width: unit * 1.35, height: height)
        case .numbers:
            SpecialKey(text: "#+=", width: unit * 1.35, height: height) { model.switchLayer(.symbols) }
        case .symbols:
            SpecialKey(text: "123", width: unit * 1.35, height: height) { model.switchLayer(.numbers) }
        }
    }

    private func bottomRow(unit: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: KeyboardMetrics.keyGap) {
            SpecialKey(text: model.layer == .letters ? "123" : "ABC", width: unit * 1.35, height: height) {
                model.switchLayer(model.layer == .letters ? .numbers : .letters)
            }
            if model.needsGlobe {
                SpecialKey(systemImage: "globe", width: unit * 1.1, height: height) { model.nextKeyboard() }
                    .accessibilityLabel("Next keyboard")
            }
            SpaceKey(height: height) { model.space() }
            ReturnKey(label: model.returnLabel, primary: model.returnIsPrimary, width: unit * 2.3, height: height) {
                model.returnKey()
            }
        }
    }
}

// MARK: - Keys

private struct KeyFace: ButtonStyle {
    var fill: Color
    var pressedFill: Color = Theme.keyPressed

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? pressedFill : fill)
                    .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
            )
            .contentShape(Rectangle())
    }
}

private struct CharacterKey: View {
    let label: String
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.font(22))
                .foregroundStyle(Theme.textEmphasis)
                .frame(width: width, height: height)
        }
        .buttonStyle(KeyFace(fill: Theme.key))
    }
}

private struct SpecialKey: View {
    var text: String?
    var systemImage: String?
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    init(text: String, width: CGFloat, height: CGFloat, action: @escaping () -> Void) {
        self.text = text
        self.width = width
        self.height = height
        self.action = action
    }

    init(systemImage: String, width: CGFloat, height: CGFloat, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.width = width
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .regular))
                } else if let text {
                    Text(text).font(Theme.font(15, .medium))
                }
            }
            .foregroundStyle(Theme.textEmphasis)
            .frame(width: width, height: height)
        }
        .buttonStyle(KeyFace(fill: Theme.keySpecial, pressedFill: Theme.key))
    }
}

private struct SpaceKey: View {
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("space")
                .font(Theme.font(15))
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .buttonStyle(KeyFace(fill: Theme.key))
    }
}

private struct ReturnKey: View {
    let label: String
    let primary: Bool
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.font(15, .medium))
                .foregroundStyle(primary ? Theme.onPrimary : Theme.textEmphasis)
                .frame(width: width, height: height)
        }
        .buttonStyle(KeyFace(fill: primary ? Theme.primary : Theme.keySpecial, pressedFill: Theme.keyPressed))
    }
}

private struct ShiftKey: View {
    @ObservedObject var model: KeyboardModel
    let width: CGFloat
    let height: CGFloat
    @State private var lastTap: Date?

    var body: some View {
        Button {
            if let lastTap, Date().timeIntervalSince(lastTap) < 0.35 {
                model.shiftDoubleTapped()
                self.lastTap = nil
            } else {
                model.shiftTapped()
                lastTap = Date()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textEmphasis)
                .frame(width: width, height: height)
        }
        .buttonStyle(KeyFace(fill: model.shift == .off ? Theme.keySpecial : Theme.key))
        .accessibilityLabel(model.shift == .locked ? "Caps lock" : "Shift")
    }

    private var icon: String {
        switch model.shift {
        case .off: return "shift"
        case .on: return "shift.fill"
        case .locked: return "capslock.fill"
        }
    }
}

/// Deletes once on touch-down, then repeats; after a second of holding it
/// deletes whole words.
private struct DeleteKey: View {
    @ObservedObject var model: KeyboardModel
    let width: CGFloat
    let height: CGFloat
    @State private var pressed = false
    @State private var timer: Timer?
    @State private var started: Date?

    var body: some View {
        Image(systemName: pressed ? "delete.left.fill" : "delete.left")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Theme.textEmphasis)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(pressed ? Theme.key : Theme.keySpecial)
                    .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { begin() } }
                    .onEnded { _ in end() }
            )
            .accessibilityElement()
            .accessibilityLabel("Delete")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.deleteBackward() }
    }

    private func begin() {
        pressed = true
        started = Date()
        model.deleteBackward()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let started else { return }
                let held = Date().timeIntervalSince(started)
                if held > 1.6 {
                    model.deleteWord()
                } else if held > 0.45 {
                    model.deleteBackward()
                }
            }
        }
    }

    private func end() {
        pressed = false
        started = nil
        timer?.invalidate()
        timer = nil
    }
}
