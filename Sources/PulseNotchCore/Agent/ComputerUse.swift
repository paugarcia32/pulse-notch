import Foundation

public struct ScreenRect: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= x + width && py >= y && py <= y + height
    }
}

/// A control exposed through the Accessibility API.
public struct AccessibleElement: Codable, Hashable, Sendable, Identifiable {
    /// Stable within one observation; derived from the element's path in the tree.
    public let id: String
    public let role: String
    public let label: String
    public let value: String?
    /// Global screen coordinates with the origin at the top-left of the main display.
    public let frame: ScreenRect?
    public let isEnabled: Bool
    /// Password and other secure fields. Their values are never read or sent.
    public let isSecure: Bool
    public let actions: [String]

    public init(
        id: String,
        role: String,
        label: String,
        value: String? = nil,
        frame: ScreenRect? = nil,
        isEnabled: Bool = true,
        isSecure: Bool = false,
        actions: [String] = []
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.value = isSecure ? nil : value
        self.frame = frame
        self.isEnabled = isEnabled
        self.isSecure = isSecure
        self.actions = actions
    }

    /// Identity that survives re-observation when the element's path changes.
    public var semanticKey: String { "\(role)|\(label)" }
}

public struct ScreenCapture: Hashable, Sendable {
    public let pngData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let displayID: UInt32
    /// The captured display's frame in global coordinates, to map image points back.
    public let displayFrame: ScreenRect

    public init(pngData: Data, pixelWidth: Int, pixelHeight: Int, displayID: UInt32, displayFrame: ScreenRect) {
        self.pngData = pngData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayID = displayID
        self.displayFrame = displayFrame
    }
}

public struct Observation: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let capturedAt: Date
    public let applicationName: String?
    public let bundleID: String?
    public let processID: Int32?
    public let windowTitle: String?
    public let windowID: UInt32?
    public let displayID: UInt32?
    public let elements: [AccessibleElement]
    public let screenshot: ScreenCapture?

    public init(
        id: UUID = UUID(),
        capturedAt: Date,
        applicationName: String?,
        bundleID: String?,
        processID: Int32? = nil,
        windowTitle: String? = nil,
        windowID: UInt32? = nil,
        displayID: UInt32? = nil,
        elements: [AccessibleElement],
        screenshot: ScreenCapture? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.applicationName = applicationName
        self.bundleID = bundleID
        self.processID = processID
        self.windowTitle = windowTitle
        self.windowID = windowID
        self.displayID = displayID
        self.elements = elements
        self.screenshot = screenshot
    }

    public func element(withID id: String) -> AccessibleElement? {
        elements.first { $0.id == id }
    }
}

public enum KeyModifier: String, Codable, Hashable, Sendable, CaseIterable {
    case command
    case option
    case control
    case shift
}

public struct KeyShortcut: Codable, Hashable, Sendable {
    public let key: String
    public let modifiers: Set<KeyModifier>

    public init(key: String, modifiers: Set<KeyModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public var displayName: String {
        let order: [KeyModifier] = [.control, .option, .shift, .command]
        let symbols = order.filter(modifiers.contains).map { modifier in
            switch modifier {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
        return symbols.joined() + key.uppercased()
    }
}

public enum ActionTarget: Hashable, Sendable {
    case element(id: String, observationID: UUID)
    /// Global coordinates, used only when semantic targeting is unavailable.
    case point(x: Double, y: Double, displayID: UInt32?, observationID: UUID)

    public var observationID: UUID {
        switch self {
        case .element(_, let id), .point(_, _, _, let id): id
        }
    }
}

public enum ScrollDirection: String, Codable, Hashable, Sendable {
    case up
    case down
    case left
    case right
}

public enum ProposedAction: Hashable, Sendable {
    case openApplication(name: String)
    case activateApplication(bundleID: String)
    case openURL(URL)
    case click(ActionTarget)
    case typeText(String, into: ActionTarget?)
    case pressKeys(KeyShortcut)
    case scroll(ScrollDirection, amount: Int, at: ActionTarget?)

    public var target: ActionTarget? {
        switch self {
        case .click(let target): target
        case .typeText(_, let target), .scroll(_, _, let target): target
        case .openApplication, .activateApplication, .openURL, .pressKeys: nil
        }
    }

    /// A short description for timelines and decision state. Typed text is
    /// summarized by length so secrets typed on request do not reach logs.
    public var summary: String {
        switch self {
        case .openApplication(let name): "Open \(name)"
        case .activateApplication(let bundleID): "Activate \(bundleID)"
        case .openURL(let url): "Open \(url.host(percentEncoded: false) ?? url.absoluteString)"
        case .click(let target): "Click \(target.summary)"
        case .typeText(let text, let target):
            "Type \(text.count) characters" + (target.map { " into \($0.summary)" } ?? "")
        case .pressKeys(let shortcut): "Press \(shortcut.displayName)"
        case .scroll(let direction, let amount, _): "Scroll \(direction.rawValue) \(amount)"
        }
    }
}

extension ActionTarget {
    var summary: String {
        switch self {
        case .element(let id, _): "element \(id)"
        case .point(let x, let y, _, _): "point (\(Int(x)), \(Int(y)))"
        }
    }
}

public enum TargetValidation: Hashable, Sendable {
    case valid(ProposedAction)
    /// The target no longer matches the screen; observe again before acting.
    case stale(String)
    case invalid(String)
}

public struct ActionResult: Hashable, Sendable {
    public let summary: String

    public init(summary: String) {
        self.summary = summary
    }
}

public enum ComputerUseError: Error, Hashable, Sendable {
    case accessibilityPermissionMissing
    case screenRecordingPermissionMissing
    case applicationNotFound(String)
    case targetUnavailable(String)
    case inputFailed(String)

    public var userMessage: String {
        switch self {
        case .accessibilityPermissionMissing:
            "Pulse Notch needs Accessibility permission to control apps."
        case .screenRecordingPermissionMissing:
            "Pulse Notch needs Screen Recording permission to capture the screen."
        case .applicationNotFound(let name): "Could not find an application named “\(name)”."
        case .targetUnavailable(let detail): "The target is no longer available: \(detail)"
        case .inputFailed(let detail): "The input could not be delivered: \(detail)"
        }
    }
}

public protocol ComputerUseExecutor: Sendable {
    func observe(includeScreenshot: Bool) async throws -> Observation
    /// Checks the action against a fresh observation immediately before execution.
    func validate(_ action: ProposedAction, against observation: Observation) async -> TargetValidation
    func execute(_ action: ProposedAction, in observation: Observation) async throws -> ActionResult
    /// Resolves an application name to a bundle identifier for restriction checks.
    func bundleID(forApplicationNamed name: String) async -> String?
}
