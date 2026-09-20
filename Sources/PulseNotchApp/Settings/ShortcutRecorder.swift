import AppKit
import SwiftUI

struct AppShortcut: Codable, Equatable {
    let key: String
    let modifiers: UInt
    let keyCode: UInt16?

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.init(key: key, modifiers: modifiers, keyCode: nil)
    }

    init(key: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16?) {
        self.key = key
        self.modifiers = modifiers.rawValue
        self.keyCode = keyCode
    }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: swiftUIModifiers)
    }

    var displayName: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return "\(flags.contains(.control) ? "⌃" : "")\(flags.contains(.option) ? "⌥" : "")\(flags.contains(.shift) ? "⇧" : "")\(flags.contains(.command) ? "⌘" : "")\(key.uppercased())"
    }

    private var swiftUIModifiers: EventModifiers {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var result: EventModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let onRecord: (AppShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onShortcut = onRecord
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.onShortcut = onRecord
        view.onCancel = onCancel
    }
}

final class ShortcutRecorderView: NSView {
    var onShortcut: ((AppShortcut) -> Void)?
    var onCancel: (() -> Void)?

    private let textField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField.stringValue = "Press hotkey…"
        textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        textField.textColor = .white
        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else {
            NSSound.beep()
            return
        }
        onShortcut?(AppShortcut(key: key, modifiers: modifiers, keyCode: event.keyCode))
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 32) }
}
