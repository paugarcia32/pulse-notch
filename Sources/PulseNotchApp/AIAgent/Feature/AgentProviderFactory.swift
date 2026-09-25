import Foundation
import PulseNotchCore

/// Builds the decision and language providers for the selected configuration,
/// starting managed local runtimes when needed. It never substitutes one provider
/// for another: a missing credential or runtime is reported as an error.
actor AgentProviderFactory {
    private let credentials: any CredentialStore
    private let runtimes: LocalRuntimeManager
    private let llamaServer: ManagedLlamaServer
    private let session: URLSession
    private var layaHelper: LayaHelperProcess?

    init(credentials: any CredentialStore, runtimes: LocalRuntimeManager, llamaServer: ManagedLlamaServer, session: URLSession = .shared) {
        self.credentials = credentials
        self.runtimes = runtimes
        self.llamaServer = llamaServer
        self.session = session
    }

    func decisionProvider(for settings: AIAgentSettings) async throws -> any DecisionProvider {
        switch settings.decisionKind {
        case .jev:
            guard let key = try credentials.secret(for: .typeSafe), !key.isEmpty else {
                throw DecisionProviderError.missingCredential
            }
            return SystemOneDecisionProvider.jev(model: settings.jevModel, apiKey: key, session: session)
        case .layaEndpoint:
            guard let url = URL(string: settings.layaEndpointURL), url.scheme != nil else {
                throw DecisionProviderError.unavailable("The Laya service URL is invalid.")
            }
            return SystemOneDecisionProvider.layaEndpoint(
                url: url,
                model: settings.layaEndpointModel,
                apiKey: try credentials.secret(for: .layaEndpoint),
                session: session
            )
        case .managedLaya:
            let checkpointID = DecisionProviderSelection.defaultLayaCheckpoint
            guard await runtimes.state(of: checkpointID).isInstalled, await runtimes.state(of: "python").isInstalled else {
                throw DecisionProviderError.unavailable("Install managed Laya in AI Agent settings.")
            }
            let helper = try await managedLayaHelper(checkpointID: checkpointID)
            let limit = runtimes.manifest.model(checkpointID)?.contextLimit ?? SystemOneDecisionProvider.layaContextLimit
            return ManagedLayaDecisionProvider(transport: helper, checkpoint: checkpointID, contextLimit: limit)
        }
    }

    func languageProvider(for settings: AIAgentSettings) async throws -> any LanguageModelProvider {
        switch settings.languageKind {
        case .openRouter:
            guard let key = try credentials.secret(for: .openRouter), !key.isEmpty else {
                throw LanguageProviderError.missingCredential
            }
            return OpenAICompatibleLanguageProvider(
                baseURL: OpenAICompatibleLanguageProvider.openRouterBaseURL,
                apiKey: key,
                flavor: .openRouter,
                session: session
            )
        case .localEndpoint:
            guard let url = URL(string: settings.localEndpointURL), url.scheme != nil else {
                throw LanguageProviderError.unreachable("The local model server URL is invalid.")
            }
            return OpenAICompatibleLanguageProvider(
                baseURL: url,
                apiKey: try credentials.secret(for: .localLanguageEndpoint),
                flavor: .local,
                session: session
            )
        case .managedLocal:
            let endpoint = try await startManagedLanguageServer(modelID: settings.localModelID)
            return OpenAICompatibleLanguageProvider(baseURL: endpoint.baseURL, apiKey: endpoint.apiKey, flavor: .local, session: session)
        }
    }

    /// The model identifier sent in requests. `llama.cpp` serves one model and
    /// accepts any name, so the catalog identifier is used.
    func startManagedLanguageServer(modelID: String) async throws -> LocalServerEndpoint {
        guard await runtimes.state(of: "llama.cpp").isInstalled else {
            throw LanguageProviderError.unreachable("Install the local model runtime in AI Agent settings.")
        }
        let files = try await runtimes.modelFiles(for: modelID)
        let contextLength = runtimes.manifest.model(modelID)?.contextLength ?? 16_384
        return try await llamaServer.start(
            executable: try await runtimes.llamaServerExecutable(),
            modelID: modelID,
            model: files.model,
            projector: files.projector,
            contextLength: contextLength
        )
    }

    private func managedLayaHelper(checkpointID: String) async throws -> LayaHelperProcess {
        if let layaHelper { return layaHelper }
        let helper = LayaHelperProcess(
            python: await runtimes.pythonExecutable,
            script: try await runtimes.layaHelperScript(),
            checkpoint: await runtimes.directory(for: checkpointID)
        )
        try await helper.start()
        layaHelper = helper
        return helper
    }

    /// Stops every managed process, for example when the agent is disabled.
    func stopManagedRuntimes() async {
        await llamaServer.stop()
        await layaHelper?.stop()
        layaHelper = nil
    }
}
