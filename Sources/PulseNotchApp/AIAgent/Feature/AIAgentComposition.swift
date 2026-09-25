import Foundation
import PulseNotchCore

extension AIAgentFeatureModel {
    /// Wires the production stores, runtimes, and providers.
    static func live(
        executor: any ComputerUseExecutor,
        availability: any DesktopAvailability,
        onComposerFocusChange: @escaping (Bool) -> Void
    ) -> AIAgentFeatureModel {
        let credentials = KeychainCredentialStore()
        let (states, continuation) = AsyncStream.makeStream(of: (String, ComponentState).self)
        var manifestError: String?
        let manifest: RuntimeManifest?
        do {
            manifest = try RuntimeManifest.bundled()
        } catch {
            manifest = nil
            manifestError = "Local runtimes are unavailable: the runtime manifest could not be read."
        }
        let runtimes = manifest.map {
            LocalRuntimeManager(manifest: $0, onStateChange: { id, state in continuation.yield((id, state)) })
        }
        let factory = runtimes.map {
            AgentProviderFactory(credentials: credentials, runtimes: $0, llamaServer: ManagedLlamaServer())
        }
        return AIAgentFeatureModel(
            makeStore: { try SQLiteAgentStore(databaseURL: SQLiteAgentStore.defaultURL()) },
            credentials: credentials,
            runtimes: runtimes,
            componentStates: states,
            factory: factory,
            executor: executor,
            availability: availability,
            settingsStore: AIAgentSettingsStore(),
            storeError: manifestError,
            onComposerFocusChange: onComposerFocusChange
        )
    }
}
