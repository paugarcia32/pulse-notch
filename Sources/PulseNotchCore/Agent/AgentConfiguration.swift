import Foundation

/// The provider that answers typed, structured questions: routing, target selection,
/// risk assessment, and outcome verification. It never produces chat responses.
public enum DecisionProviderSelection: Codable, Hashable, Sendable {
    /// TypeSafe's hosted JEV model through the System One API.
    case jev(model: String)
    /// Laya running in the Pulse Notch managed runtime.
    case managedLaya(checkpoint: String)
    /// An existing service that implements the System One API, such as `laya-serve`.
    case layaEndpoint(url: URL, model: String)

    public static let defaultJEVModel = "jev-latest"
    public static let defaultLayaCheckpoint = "laya-multilingual"

    public var isLocal: Bool {
        switch self {
        case .jev: false
        case .managedLaya: true
        case .layaEndpoint(let url, _): url.isLoopback
        }
    }

    public var displayName: String {
        switch self {
        case .jev: "JEV (TypeSafe)"
        case .managedLaya: "Laya (managed)"
        case .layaEndpoint: "Laya (existing service)"
        }
    }
}

/// The provider for conversation, planning, text generation, and visual reasoning.
public enum LanguageProviderSelection: Codable, Hashable, Sendable {
    case openRouter(model: String)
    /// A model served by the Pulse Notch managed `llama.cpp` runtime.
    case managedLocal(modelID: String)
    /// An existing OpenAI-compatible server.
    case localEndpoint(url: URL, model: String)

    public var isLocal: Bool {
        switch self {
        case .openRouter: false
        case .managedLocal: true
        case .localEndpoint(let url, _): url.isLoopback
        }
    }

    public var modelID: String {
        switch self {
        case .openRouter(let model): model
        case .managedLocal(let modelID): modelID
        case .localEndpoint(_, let model): model
        }
    }

    public var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .managedLocal: "Local model (managed)"
        case .localEndpoint: "Local model (existing server)"
        }
    }
}

public enum ExecutionMode: String, Codable, CaseIterable, Hashable, Sendable {
    /// Proceeds without confirming each step, within the instruction and permissions.
    case autonomous
    /// Asks for approval before every desktop action.
    case supervised
}

/// Applications the agent may or may not control. An empty allow list means every
/// application that is not denied is allowed.
public struct ApplicationRestrictions: Codable, Hashable, Sendable {
    public var allowedBundleIDs: Set<String>
    public var deniedBundleIDs: Set<String>

    public init(allowedBundleIDs: Set<String> = [], deniedBundleIDs: Set<String> = []) {
        self.allowedBundleIDs = allowedBundleIDs
        self.deniedBundleIDs = deniedBundleIDs
    }

    public func permits(bundleID: String?) -> Bool {
        guard let bundleID else { return allowedBundleIDs.isEmpty }
        if deniedBundleIDs.contains(bundleID) { return false }
        return allowedBundleIDs.isEmpty || allowedBundleIDs.contains(bundleID)
    }
}

public struct RunLimits: Codable, Hashable, Sendable {
    public static let defaultMaximumActions = 50
    public static let defaultMaximumDuration: TimeInterval = 10 * 60
    public static let defaultMaximumReplans = 2

    public var maximumActions: Int
    public var maximumDuration: TimeInterval
    /// How many times a run re-observes and replans after a recoverable failure
    /// before it pauses with an explanation.
    public var maximumReplans: Int

    public init(
        maximumActions: Int = Self.defaultMaximumActions,
        maximumDuration: TimeInterval = Self.defaultMaximumDuration,
        maximumReplans: Int = Self.defaultMaximumReplans
    ) {
        self.maximumActions = max(1, maximumActions)
        self.maximumDuration = max(1, maximumDuration)
        self.maximumReplans = max(0, maximumReplans)
    }

    public static let `default` = RunLimits()
}

public struct AgentConfiguration: Codable, Hashable, Sendable {
    public var decision: DecisionProviderSelection
    public var language: LanguageProviderSelection
    public var executionMode: ExecutionMode
    public var restrictions: ApplicationRestrictions
    public var limits: RunLimits
    /// Whether desktop tools are offered to the model at all.
    public var computerUseEnabled: Bool
    /// Set only after the selected language model passed a vision capability check.
    public var visionVerified: Bool
    /// When computer use was requested but is unavailable, the reason to tell the user.
    public var computerUseUnavailableReason: String?

    public init(
        decision: DecisionProviderSelection,
        language: LanguageProviderSelection,
        executionMode: ExecutionMode = .autonomous,
        restrictions: ApplicationRestrictions = ApplicationRestrictions(),
        limits: RunLimits = .default,
        computerUseEnabled: Bool = true,
        visionVerified: Bool = false,
        computerUseUnavailableReason: String? = nil
    ) {
        self.decision = decision
        self.language = language
        self.executionMode = executionMode
        self.restrictions = restrictions
        self.limits = limits
        self.computerUseEnabled = computerUseEnabled
        self.visionVerified = visionVerified
        self.computerUseUnavailableReason = computerUseUnavailableReason
    }

    /// True only when both inference providers run on this Mac. Browsing or using
    /// online applications can still reach the network.
    public var isFullyLocalInference: Bool { decision.isLocal && language.isLocal }
}

extension URL {
    public var isLoopback: Bool {
        guard let host = host(percentEncoded: false)?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}
