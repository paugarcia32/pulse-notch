import CoreGraphics
import Foundation
import PulseNotchCore

/// Splits text into keyboard-event payloads without breaking grapheme clusters.
enum TextChunking {
    static let maximumUTF16Units = 20

    static func chunks(of text: String, maximumUTF16Units: Int = maximumUTF16Units) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(character.utf16)
            if !current.isEmpty, current.count + units.count > maximumUTF16Units {
                chunks.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

enum ScrollDeltas {
    static let maximumLines = 50

    /// Quartz wheel deltas: positive vertical scrolls up and positive horizontal scrolls left.
    static func lines(for direction: ScrollDirection, amount: Int) -> (vertical: Int32, horizontal: Int32) {
        let lines = Int32(min(max(amount, 1), maximumLines))
        switch direction {
        case .up: return (lines, 0)
        case .down: return (-lines, 0)
        case .left: return (0, lines)
        case .right: return (0, -lines)
        }
    }
}

/// Posts synthesized mouse, keyboard, and scroll events. Posting requires Accessibility trust.
enum InputSynthesizer {
    private static let chunkDelay: Duration = .milliseconds(10)

    static func click(at point: CGPoint) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        try post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        try post(down)
        try post(up)
    }

    static func type(_ text: String) async throws {
        let source = CGEventSource(stateID: .hidSystemState)
        for chunk in TextChunking.chunks(of: text) {
            try Task.checkCancellation()
            for isKeyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isKeyDown) else {
                    throw ComputerUseError.inputFailed("The keyboard event could not be created.")
                }
                // Held modifier keys would otherwise turn typed text into shortcuts.
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: chunkDelay)
        }
    }

    static func press(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isKeyDown)
            event?.flags = flags
            try post(event)
        }
    }

    static func scroll(_ direction: ScrollDirection, amount: Int, at point: CGPoint?) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        if let point {
            try post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
        }
        let deltas = ScrollDeltas.lines(for: direction, amount: amount)
        try post(CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 2,
            wheel1: deltas.vertical,
            wheel2: deltas.horizontal,
            wheel3: 0
        ))
    }

    private static func post(_ event: CGEvent?) throws {
        guard let event else { throw ComputerUseError.inputFailed("The input event could not be created.") }
        event.post(tap: .cghidEventTap)
    }
}
