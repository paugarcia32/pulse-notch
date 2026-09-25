import ApplicationServices
import CoreGraphics
import Foundation
import PulseNotchCore

enum AXName {
    static let role = "AXRole"
    static let subrole = "AXSubrole"
    static let title = "AXTitle"
    static let description = "AXDescription"
    static let label = "AXLabel"
    static let placeholder = "AXPlaceholderValue"
    static let help = "AXHelp"
    static let value = "AXValue"
    static let enabled = "AXEnabled"
    static let position = "AXPosition"
    static let size = "AXSize"
    static let children = "AXChildren"
    static let focused = "AXFocused"
    static let focusedWindow = "AXFocusedWindow"
    static let focusedElement = "AXFocusedUIElement"
    static let mainWindow = "AXMainWindow"
    static let windows = "AXWindows"
    static let pressAction = "AXPress"
}

/// A thin, synchronous wrapper around one `AXUIElement`.
///
/// Accessibility calls block on inter-process messaging, so callers keep them off
/// the main actor.
struct AccessibilityNode {
    static let messagingTimeout: Float = 1.0

    let element: AXUIElement

    static func application(processID: pid_t) -> AccessibilityNode {
        let element = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return AccessibilityNode(element: element)
    }

    static func systemWide() -> AccessibilityNode {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return AccessibilityNode(element: element)
    }

    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// Reads several attributes in one round trip; missing attributes are absent.
    func attributes(_ names: [String]) -> [String: CFTypeRef] {
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            element,
            names as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )
        guard result == .success, let array = values as? [AnyObject], array.count == names.count else { return [:] }
        var output: [String: CFTypeRef] = [:]
        for (name, value) in zip(names, array) where !Self.isErrorPlaceholder(value) {
            output[name] = value
        }
        return output
    }

    func string(_ name: String) -> String? {
        attribute(name) as? String
    }

    func node(_ name: String) -> AccessibilityNode? {
        attribute(name).flatMap(Self.element(from:)).map(AccessibilityNode.init(element:))
    }

    func nodes(_ name: String) -> [AccessibilityNode] {
        guard let array = attribute(name) as? [AnyObject] else { return [] }
        return array.compactMap(Self.element(from:)).map(AccessibilityNode.init(element:))
    }

    func children(limit: Int) -> [AccessibilityNode] {
        guard limit > 0 else { return [] }
        var values: CFArray?
        let result = AXUIElementCopyAttributeValues(element, AXName.children as CFString, 0, limit, &values)
        guard result == .success, let array = values as? [AnyObject] else { return [] }
        return array.compactMap(Self.element(from:)).map(AccessibilityNode.init(element:))
    }

    var frame: ScreenRect? {
        let values = attributes([AXName.position, AXName.size])
        return Self.frame(position: values[AXName.position], size: values[AXName.size])
    }

    var actionNames: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    func setFocused() -> Bool {
        AXUIElementSetAttributeValue(element, AXName.focused as CFString, kCFBooleanTrue) == .success
    }

    var isSecure: Bool {
        let values = attributes([AXName.role, AXName.subrole])
        guard let role = values[AXName.role] as? String else { return false }
        return AccessibleRoleFilter.isSecure(role: role, subrole: values[AXName.subrole] as? String)
    }

    static func frame(position: CFTypeRef?, size: CFTypeRef?) -> ScreenRect? {
        guard let position = axValue(position, type: .cgPoint), let size = axValue(size, type: .cgSize) else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return ScreenRect(x: origin.x, y: origin.y, width: extent.width, height: extent.height)
    }

    static func stringValue(_ value: CFTypeRef?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func axValue(_ value: CFTypeRef?, type: AXValueType) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private static func element(from value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func isErrorPlaceholder(_ value: AnyObject) -> Bool {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        return AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError
    }
}

/// The live element behind an identifier, kept so actions reach the exact control observed.
struct LiveElement {
    let node: AccessibilityNode
    let role: String
    let isSecure: Bool
    let frame: ScreenRect?
    let actions: [String]
}

struct AccessibilityTreeSnapshot {
    var elements: [AccessibleElement] = []
    var live: [String: LiveElement] = [:]
}

/// Breadth-first walk over a window's Accessibility tree with depth and size caps.
struct AccessibilityTreeWalker {
    var maximumDepth = 12
    var maximumElements = 400
    var maximumVisitedNodes = 4000
    var maximumChildrenPerNode = 300

    func walk(root: AccessibilityNode) -> AccessibilityTreeSnapshot {
        var snapshot = AccessibilityTreeSnapshot()
        var queue: [(node: AccessibilityNode, path: [Int])] = [(root, [])]
        var head = 0
        while head < queue.count,
              snapshot.elements.count < maximumElements,
              head < maximumVisitedNodes,
              !Task.isCancelled {
            let (node, path) = queue[head]
            head += 1
            let identity = node.attributes([AXName.role, AXName.subrole])
            guard let role = identity[AXName.role] as? String else { continue }
            if AccessibleRoleFilter.isCandidate(role: role) {
                let subrole = identity[AXName.subrole] as? String
                record(node, role: role, subrole: subrole, path: path, into: &snapshot)
            }
            guard path.count < maximumDepth else { continue }
            let remaining = maximumVisitedNodes - queue.count
            for (index, child) in node.children(limit: min(maximumChildrenPerNode, remaining)).enumerated() {
                queue.append((child, path + [index]))
            }
        }
        return snapshot
    }

    private func record(
        _ node: AccessibilityNode,
        role: String,
        subrole: String?,
        path: [Int],
        into snapshot: inout AccessibilityTreeSnapshot
    ) {
        let isSecure = AccessibleRoleFilter.isSecure(role: role, subrole: subrole)
        var names = [
            AXName.title, AXName.description, AXName.label, AXName.placeholder,
            AXName.help, AXName.enabled, AXName.position, AXName.size
        ]
        // Secure field values are never requested from the target app.
        if !isSecure { names.append(AXName.value) }
        let details = node.attributes(names)
        let isStaticText = role == AccessibleRoleFilter.staticTextRole
        let rawValue = isSecure ? nil : AccessibilityNode.stringValue(details[AXName.value])
        let label = AccessibleLabel.first(of: [
            details[AXName.title] as? String,
            details[AXName.description] as? String,
            details[AXName.label] as? String,
            details[AXName.placeholder] as? String,
            details[AXName.help] as? String,
            isStaticText ? rawValue : nil
        ])
        guard AccessibleRoleFilter.keeps(role: role, label: label) else { return }
        let value = isStaticText ? nil : rawValue.map { AccessibleLabel.truncated($0, to: AccessibleLabel.maximumValueLength) }
        let frame = AccessibilityNode.frame(position: details[AXName.position], size: details[AXName.size])
        let actions = node.actionNames
        let id = ElementIdentity.uniqueID(path: path, role: role, isTaken: { snapshot.live[$0] != nil })
        snapshot.elements.append(AccessibleElement(
            id: id,
            role: isSecure ? AccessibleRoleFilter.secureTextFieldRole : role,
            label: label,
            value: value,
            frame: frame,
            isEnabled: (details[AXName.enabled] as? Bool) ?? true,
            isSecure: isSecure,
            actions: actions
        ))
        snapshot.live[id] = LiveElement(node: node, role: role, isSecure: isSecure, frame: frame, actions: actions)
    }
}
