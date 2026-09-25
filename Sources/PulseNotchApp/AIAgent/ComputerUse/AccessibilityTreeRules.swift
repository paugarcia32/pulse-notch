import Foundation
import PulseNotchCore

/// Decides which Accessibility elements are worth showing the agent.
enum AccessibleRoleFilter {
    static let staticTextRole = "AXStaticText"
    static let secureTextFieldRole = "AXSecureTextField"

    static let actionableRoles: Set<String> = [
        "AXButton",
        "AXTextField",
        "AXTextArea",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXLink",
        "AXComboBox",
        "AXSlider",
        "AXIncrementor",
        secureTextFieldRole
    ]

    /// Structural roles that only help the agent when they carry a title.
    static let titledRoles: Set<String> = ["AXRow", "AXCell"]

    /// Whether the element's details are worth reading at all.
    static func isCandidate(role: String) -> Bool {
        actionableRoles.contains(role) || titledRoles.contains(role) || role == staticTextRole
    }

    static func keeps(role: String, label: String) -> Bool {
        if actionableRoles.contains(role) { return true }
        if titledRoles.contains(role) || role == staticTextRole { return !label.isEmpty }
        return false
    }

    static func isSecure(role: String, subrole: String?) -> Bool {
        role == secureTextFieldRole || subrole == secureTextFieldRole
    }
}

enum AccessibleLabel {
    static let maximumLabelLength = 200
    static let maximumValueLength = 500

    /// The first non-empty candidate, trimmed and shortened to keep prompts small.
    static func first(of candidates: [String?]) -> String {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                continue
            }
            return truncated(trimmed, to: maximumLabelLength)
        }
        return ""
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}

/// Derives element identifiers from an element's child-index path so the same
/// control keeps its identifier across observations while the window layout is unchanged.
enum ElementIdentity {
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    private static let tokenLength = 6

    static func id(path: [Int], role: String) -> String {
        token(for: pathKey(path) + "|" + role)
    }

    /// Resolves the rare hash collision within one observation deterministically.
    static func uniqueID(path: [Int], role: String, isTaken: (String) -> Bool) -> String {
        let base = pathKey(path) + "|" + role
        var candidate = token(for: base)
        var salt = 1
        while isTaken(candidate) {
            candidate = token(for: base + "#\(salt)")
            salt += 1
        }
        return candidate
    }

    static func pathKey(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: ".")
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func token(for key: String) -> String {
        var value = fnv1a(key)
        var characters: [Character] = []
        for _ in 0..<tokenLength {
            characters.append(alphabet[Int(value % 36)])
            value /= 36
        }
        return "e" + String(characters.reversed())
    }
}

struct WindowCandidate: Equatable, Sendable {
    let id: UInt32
    let frame: ScreenRect
    let title: String?
}

/// Matches an Accessibility window to its window-server identifier without private API.
enum WindowMatcher {
    static func match(_ candidates: [WindowCandidate], frame: ScreenRect, title: String?, tolerance: Double = 2) -> UInt32? {
        let sameFrame = candidates.filter { candidate in
            abs(candidate.frame.x - frame.x) <= tolerance
                && abs(candidate.frame.y - frame.y) <= tolerance
                && abs(candidate.frame.width - frame.width) <= tolerance
                && abs(candidate.frame.height - frame.height) <= tolerance
        }
        if sameFrame.count == 1 { return sameFrame[0].id }
        guard let title, !title.isEmpty else { return nil }
        let sameTitle = sameFrame.filter { $0.title == title }
        return sameTitle.count == 1 ? sameTitle[0].id : nil
    }
}
