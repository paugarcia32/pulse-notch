import Foundation
import PulseNotchCore

/// User-facing AI Agent configuration. Credentials are stored separately in Keychain.
struct AIAgentSettings: Codable, Hashable, Sendable {
    enum DecisionKind: String, Codable, CaseIterable, Identifiable, Sendable {
        case jev
        case managedLaya
        case layaEndpoint

        var id: String { rawValue }

        var title: String {
            switch self {
            case .jev: "JEV (TypeSafe, hosted)"
            case .managedLaya: "Laya (managed on this Mac)"
            case .layaEndpoint: "Laya (existing service)"
            }
        }
    }

    enum LanguageKind: String, Codable, CaseIterable, Identifiable, Sendable {
        case openRouter
        case managedLocal
        case localEndpoint

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openRouter: "OpenRouter (hosted)"
            case .managedLocal: "Local model (managed on this Mac)"
            case .localEndpoint: "Local model (existing server)"
            }
        }
    }

    static let defaultLocalModelID = "mimo-v2.6-distill-qwen-9b-q8_0"
    static let defaultRetentionDays = 30

    var decisionKind: DecisionKind = .jev
    var jevModel: String = DecisionProviderSelection.defaultJEVModel
    var layaEndpointURL: String = "http://127.0.0.1:8000"
    var layaEndpointModel: String = DecisionProviderSelection.defaultLayaCheckpoint

    var languageKind: LanguageKind = .openRouter
    var openRouterModel: String = ""
    var localModelID: String = defaultLocalModelID
    var localEndpointURL: String = "http://127.0.0.1:8080/v1"
    var localEndpointModel: String = ""

    var executionMode: ExecutionMode = .autonomous
    var deniedBundleIDs: [String] = []
    var allowedBundleIDs: [String] = []
    var limits: RunLimits = .default
    var computerUseEnabled: Bool = false
    var retentionDays: Int = defaultRetentionDays
    var hostedDataDisclosureAccepted: Bool = false
    /// Capability checks keyed by `CapabilityKey`, so a model is never assumed ready.
    var capabilityReports: [String: CapabilityReport] = [:]

    init() {}

    /// Decodes settings saved by any earlier version, keeping defaults for new fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AIAgentSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        decisionKind = value(.decisionKind, defaults.decisionKind)
        jevModel = value(.jevModel, defaults.jevModel)
        layaEndpointURL = value(.layaEndpointURL, defaults.layaEndpointURL)
        layaEndpointModel = value(.layaEndpointModel, defaults.layaEndpointModel)
        languageKind = value(.languageKind, defaults.languageKind)
        openRouterModel = value(.openRouterModel, defaults.openRouterModel)
        localModelID = value(.localModelID, defaults.localModelID)
        localEndpointURL = value(.localEndpointURL, defaults.localEndpointURL)
        localEndpointModel = value(.localEndpointModel, defaults.localEndpointModel)
        executionMode = value(.executionMode, defaults.executionMode)
        deniedBundleIDs = value(.deniedBundleIDs, defaults.deniedBundleIDs)
        allowedBundleIDs = value(.allowedBundleIDs, defaults.allowedBundleIDs)
        limits = value(.limits, defaults.limits)
        computerUseEnabled = value(.computerUseEnabled, defaults.computerUseEnabled)
        retentionDays = value(.retentionDays, defaults.retentionDays)
        hostedDataDisclosureAccepted = value(.hostedDataDisclosureAccepted, defaults.hostedDataDisclosureAccepted)
        capabilityReports = value(.capabilityReports, defaults.capabilityReports)
    }

    var decisionSelection: DecisionProviderSelection {
        switch decisionKind {
        case .jev: .jev(model: jevModel)
        case .managedLaya: .managedLaya(checkpoint: DecisionProviderSelection.defaultLayaCheckpoint)
        case .layaEndpoint:
            .layaEndpoint(url: URL(string: layaEndpointURL) ?? URL(fileURLWithPath: "/"), model: layaEndpointModel)
        }
    }

    var languageSelection: LanguageProviderSelection {
        switch languageKind {
        case .openRouter: .openRouter(model: openRouterModel)
        case .managedLocal: .managedLocal(modelID: localModelID)
        case .localEndpoint:
            .localEndpoint(url: URL(string: localEndpointURL) ?? URL(fileURLWithPath: "/"), model: localEndpointModel)
        }
    }

    var capabilityKey: String { "\(languageKind.rawValue)|\(languageSelection.modelID)" }
    var capabilityReport: CapabilityReport? { capabilityReports[capabilityKey] }

    var usesHostedProvider: Bool { !decisionSelection.isLocal || !languageSelection.isLocal }

    func configuration(limits override: RunLimits? = nil) -> AgentConfiguration {
        AgentConfiguration(
            decision: decisionSelection,
            language: languageSelection,
            executionMode: executionMode,
            restrictions: ApplicationRestrictions(allowedBundleIDs: Set(allowedBundleIDs), deniedBundleIDs: Set(deniedBundleIDs)),
            limits: override ?? limits,
            computerUseEnabled: computerUseEnabled && (capabilityReport?.toolCallsVerified ?? false),
            visionVerified: capabilityReport?.visionVerified ?? false
        )
    }

    /// Reports what is missing before the agent can run with these settings.
    func setupIssues(hasCredential: (CredentialAccount) -> Bool) -> [String] {
        var issues: [String] = []
        switch decisionKind {
        case .jev where !hasCredential(.typeSafe): issues.append("Add a TypeSafe API key for JEV.")
        case .layaEndpoint where URL(string: layaEndpointURL)?.scheme == nil: issues.append("Enter the Laya service URL.")
        default: break
        }
        switch languageKind {
        case .openRouter:
            if !hasCredential(.openRouter) { issues.append("Add an OpenRouter API key.") }
            if openRouterModel.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("Choose an OpenRouter model.") }
        case .localEndpoint:
            if URL(string: localEndpointURL)?.scheme == nil { issues.append("Enter the local model server URL.") }
            if localEndpointModel.trimmingCharacters(in: .whitespaces).isEmpty { issues.append("Enter the local model ID.") }
        case .managedLocal:
            break
        }
        return issues
    }
}

/// Persists AI Agent settings in user defaults. Only non-secret values are stored.
struct AIAgentSettingsStore {
    private static let key = "settings.aiAgent"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AIAgentSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(AIAgentSettings.self, from: data)
        else { return AIAgentSettings() }
        return settings
    }

    func save(_ settings: AIAgentSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
