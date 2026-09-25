import Carbon.HIToolbox
import CoreGraphics
import Foundation
import PulseNotchCore

/// Maps the key names the agent uses to virtual key codes and event flags.
///
/// Virtual key codes identify physical key positions on an ANSI keyboard, so a
/// letter shortcut presses the key at that letter's US position regardless of
/// the active input layout.
enum KeyCodeMap {
    static func keyCode(for name: String) -> CGKeyCode? {
        guard let normalized = normalizedName(name) else { return nil }
        guard let code = namedKeys[normalized] ?? characterKeys[normalized] else { return nil }
        return CGKeyCode(code)
    }

    static func flags(for modifiers: Set<KeyModifier>) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
    }

    private static func normalizedName(_ name: String) -> String? {
        if name == " " { return "space" }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > 1 else { return trimmed }
        return trimmed.filter { !" -_".contains($0) }
    }

    private static let namedKeys: [String: Int] = [
        "return": kVK_Return,
        "enter": kVK_Return,
        "tab": kVK_Tab,
        "space": kVK_Space,
        "escape": kVK_Escape,
        "esc": kVK_Escape,
        "delete": kVK_Delete,
        "backspace": kVK_Delete,
        "forwarddelete": kVK_ForwardDelete,
        "up": kVK_UpArrow,
        "uparrow": kVK_UpArrow,
        "down": kVK_DownArrow,
        "downarrow": kVK_DownArrow,
        "left": kVK_LeftArrow,
        "leftarrow": kVK_LeftArrow,
        "right": kVK_RightArrow,
        "rightarrow": kVK_RightArrow,
        "home": kVK_Home,
        "end": kVK_End,
        "pageup": kVK_PageUp,
        "pagedown": kVK_PageDown,
        "f1": kVK_F1,
        "f2": kVK_F2,
        "f3": kVK_F3,
        "f4": kVK_F4,
        "f5": kVK_F5,
        "f6": kVK_F6,
        "f7": kVK_F7,
        "f8": kVK_F8,
        "f9": kVK_F9,
        "f10": kVK_F10,
        "f11": kVK_F11,
        "f12": kVK_F12
    ]

    private static let characterKeys: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ",": kVK_ANSI_Comma,
        ".": kVK_ANSI_Period,
        "/": kVK_ANSI_Slash,
        ";": kVK_ANSI_Semicolon,
        "'": kVK_ANSI_Quote,
        "[": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket,
        "-": kVK_ANSI_Minus,
        "=": kVK_ANSI_Equal,
        "`": kVK_ANSI_Grave,
        "\\": kVK_ANSI_Backslash
    ]
}
