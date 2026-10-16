import AppKit
import Carbon

/// Types a finished dictation into whatever app has focus, the way a person
/// would: puts it on the clipboard, presses ⌘V, then puts back what the
/// clipboard held before (unless the user wants dictations kept there).
enum TextInserter {
    /// Pasting into other apps needs Privacy & Security › Accessibility.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt to allow Accessibility, with a button to
    /// System Settings.
    static func requestTrust() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Clipboard managers that follow nspasteboard.org leave entries marked
    /// this way out of their history.
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Returns false when the text could only be copied (no Accessibility),
    /// so the caller can say "press ⌘V".
    @MainActor
    static func insert(_ text: String, keepOnClipboard: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = keepOnClipboard ? [] : snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard isTrusted else { return false }
        if !keepOnClipboard { pasteboard.setData(Data(), forType: transient) }

        pressPaste()

        guard !keepOnClipboard else { return true }
        let ours = pasteboard.changeCount
        // The target app reads the clipboard when it handles ⌘V, a moment
        // after the keystroke; put the old contents back after that, unless
        // something else has written to the clipboard meanwhile.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pasteboard.changeCount == ours else { return }
            restore(saved, to: pasteboard)
        }
        return true
    }

    /// Whether the character before the cursor is part of a word, so the
    /// dictation needs a space in front ("Hello there." then "How are you").
    /// Asked through Accessibility; an app that doesn't say gets no space.
    @MainActor
    static func needsLeadingSpace() -> Bool {
        guard isTrusted, let field = focusedElement(),
              let cursor = selectedRange(field), cursor.location > 0,
              let before = character(in: field, at: cursor.location - 1)
        else { return false }
        return !before.isWhitespace && !"([{\"'“‘/-".contains(before)
    }

    private static func focusedElement() -> AXUIElement? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        return (focused as! AXUIElement)
    }

    private static func selectedRange(_ field: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    /// The character at a UTF-16 offset: asked for directly, or read out of
    /// the field's whole value for apps that only offer that.
    private static func character(in field: AXUIElement, at offset: Int) -> Character? {
        var range = CFRange(location: offset, length: 1)
        if let parameter = AXValueCreate(.cfRange, &range) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(field, kAXStringForRangeParameterizedAttribute as CFString,
                                                          parameter, &value) == .success,
               let text = value as? String, let last = text.last {
                return last
            }
        }
        var whole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &whole) == .success,
              let text = whole as? String
        else { return nil }
        let utf16 = text.utf16
        guard offset < utf16.count,
              let index = utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex),
              let position = index.samePosition(in: text)
        else { return nil }
        return text[position]
    }

    private static func pressPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// The key that types `character` on the user's keyboard layout, so ⌘V
    /// is right on Dvorak, AZERTY and the rest. Command shortcuts follow the
    /// ASCII-capable layout, which is why that's the one asked for.
    private static func keyCode(for character: String) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == character {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    private static func snapshot(_ pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
