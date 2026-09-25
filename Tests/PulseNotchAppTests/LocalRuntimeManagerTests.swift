import CryptoKit
import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

private struct FakeDownloader: FileDownloading {
    /// Contents served per URL; a missing URL fails like an offline network.
    let files: [URL: Data]
    let requests = Locked<[URL]>([])
    var delay: Duration?

    func download(_ url: URL, to destination: URL, expectedSize: Int64, progress: @escaping @Sendable (Int64) -> Void) async throws {
        requests.withValue { $0.append(url) }
        if let delay { try await Task.sleep(for: delay) }
        guard let data = files[url] else { throw RuntimeError.downloadFailed("offline") }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination)
        progress(Int64(data.count))
    }
}

private struct FakeCommands: CommandRunning {
    let runs = Locked<[[String]]>([])
    var failPip = false

    func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> CommandResult {
        runs.withValue { $0.append([executable.lastPathComponent] + arguments) }
        if executable.lastPathComponent == "tar", let index = arguments.firstIndex(of: "-C") {
            let destination = URL(fileURLWithPath: arguments[index + 1])
            let binary = destination.appending(path: "build/bin/llama-server")
            try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh".utf8))
        }
        if failPip, arguments.contains("pip") { return CommandResult(status: 1, output: "ERROR: hash mismatch") }
        return CommandResult(status: 0, output: "")
    }
}

struct LocalRuntimeManagerTests {
    private static let modelData = Data("GGUF-model-bytes".utf8)
    private static let archiveData = Data("archive".utf8)

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func manifest(modelSHA: String = sha256(modelData)) -> RuntimeManifest {
        RuntimeManifest(
            manifestVersion: 1,
            runtimes: [RuntimeManifest.Runtime(
                id: "llama.cpp",
                name: "llama.cpp",
                version: "b1",
                license: "MIT",
                source: URL(string: "https://example.com")!,
                minimumMacOS: "14.0",
                architectures: ["arm64"],
                archive: .init(url: URL(string: "https://example.com/llama.tar.gz")!, size: Int64(archiveData.count), sha256: sha256(archiveData)),
                packages: nil,
                executable: "llama-server"
            )],
            decisionModels: [],
            languageModels: [RuntimeManifest.Model(
                id: "tiny",
                name: "Tiny",
                repository: "org/tiny",
                revision: "abc",
                license: "MIT",
                runtime: "llama.cpp",
                files: [.init(path: "tiny.gguf", role: .model, size: Int64(modelData.count), sha256: modelSHA, gitBlobSHA1: nil)],
                upstream: nil,
                contextLimit: nil,
                contextLength: 4_096,
                minimumMemoryGB: nil,
                notes: nil
            )]
        )
    }

    private func withRoot(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PulseNotchRuntimeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    private var servedFiles: [URL: Data] {
        [
            URL(string: "https://example.com/llama.tar.gz")!: Self.archiveData,
            URL(string: "https://huggingface.co/org/tiny/resolve/abc/tiny.gguf")!: Self.modelData
        ]
    }

    @Test
    func installsVerifiesAndReusesAModelOffline() async throws {
        try await withRoot { root in
            let downloader = FakeDownloader(files: servedFiles)
            let manager = LocalRuntimeManager(manifest: Self.manifest(), root: root, downloader: downloader, commands: FakeCommands(), availableCapacity: { _ in 10_000_000 })
            try await manager.install("tiny")

            #expect(await manager.state(of: "tiny") == .installed(version: "abc"))
            #expect(await manager.state(of: "llama.cpp") == .installed(version: "b1"))
            #expect(try await manager.llamaServerExecutable().lastPathComponent == "llama-server")
            #expect(try await manager.modelFiles(for: "tiny").model.lastPathComponent == "tiny.gguf")

            let offline = LocalRuntimeManager(manifest: Self.manifest(), root: root, downloader: FakeDownloader(files: [:]), commands: FakeCommands(), availableCapacity: { _ in 10_000_000 })
            try await offline.install("tiny")
            #expect(await offline.state(of: "tiny").isInstalled)
        }
    }

    @Test
    func checksumMismatchesRemoveTheFileAndFail() async throws {
        try await withRoot { root in
            let manager = LocalRuntimeManager(
                manifest: Self.manifest(modelSHA: String(repeating: "0", count: 64)),
                root: root,
                downloader: FakeDownloader(files: servedFiles),
                commands: FakeCommands(),
                availableCapacity: { _ in 10_000_000 }
            )
            await #expect(throws: RuntimeError.checksumMismatch("tiny.gguf")) { try await manager.install("tiny") }
            guard case .failed = await manager.state(of: "tiny") else {
                Issue.record("Expected a failed state")
                return
            }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "models/tiny/tiny.gguf.partial").path))
        }
    }

    @Test
    func insufficientDiskSpaceStopsBeforeDownloading() async throws {
        try await withRoot { root in
            let downloader = FakeDownloader(files: servedFiles)
            let manager = LocalRuntimeManager(manifest: Self.manifest(), root: root, downloader: downloader, commands: FakeCommands(), availableCapacity: { _ in 1 })
            await #expect(throws: RuntimeError.self) { try await manager.install("llama.cpp") }
            #expect(downloader.requests.current.isEmpty)
        }
    }

    @Test
    func failedDownloadsCanBeRetried() async throws {
        try await withRoot { root in
            let failing = LocalRuntimeManager(manifest: Self.manifest(), root: root, downloader: FakeDownloader(files: [:]), commands: FakeCommands(), availableCapacity: { _ in 10_000_000 })
            await #expect(throws: RuntimeError.downloadFailed("offline")) { try await failing.install("llama.cpp") }

            let retrying = LocalRuntimeManager(manifest: Self.manifest(), root: root, downloader: FakeDownloader(files: servedFiles), commands: FakeCommands(), availableCapacity: { _ in 10_000_000 })
            try await retrying.install("llama.cpp")
            #expect(await retrying.state(of: "llama.cpp").isInstalled)
        }
    }

    @Test
    func cancellingAnInstallLeavesItNotInstalled() async throws {
        try await withRoot { root in
            var downloader = FakeDownloader(files: servedFiles)
            downloader.delay = .seconds(30)
            let manager = LocalRuntimeManager(manifest: Self.manifest(), root: root, downloader: downloader, commands: FakeCommands(), availableCapacity: { _ in 10_000_000 })
            let task = Task { try await manager.install("llama.cpp") }
            while downloader.requests.current.isEmpty { await Task.yield() }
            task.cancel()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(await manager.state(of: "llama.cpp") == .notInstalled)
        }
    }

    @Test
    func removalDeletesOnlyTheRequestedComponent() async throws {
        try await withRoot { root in
            let manager = LocalRuntimeManager(manifest: Self.manifest(), root: root, downloader: FakeDownloader(files: servedFiles), commands: FakeCommands(), availableCapacity: { _ in 10_000_000 })
            try await manager.install("tiny")
            try await manager.remove("tiny")

            #expect(await manager.state(of: "tiny") == .notInstalled)
            #expect(await manager.state(of: "llama.cpp").isInstalled)
        }
    }

    @Test
    func pythonPackageFailuresAreReported() async throws {
        try await withRoot { root in
            let archive = Self.archiveData
            let manifest = RuntimeManifest(
                manifestVersion: 1,
                runtimes: [RuntimeManifest.Runtime(
                    id: "python",
                    name: "Python",
                    version: "3.12",
                    license: "PSF-2.0",
                    source: URL(string: "https://example.com")!,
                    minimumMacOS: "14.0",
                    architectures: ["arm64"],
                    archive: .init(url: URL(string: "https://example.com/llama.tar.gz")!, size: Int64(archive.count), sha256: Self.sha256(archive)),
                    packages: .init(lockFile: "laya-requirements.lock", requirement: "laya-mlx==0.2.0", estimatedSize: 10),
                    executable: nil
                )],
                decisionModels: [],
                languageModels: []
            )
            var commands = FakeCommands()
            commands.failPip = true
            let manager = LocalRuntimeManager(
                manifest: manifest,
                root: root,
                downloader: FakeDownloader(files: servedFiles),
                commands: commands,
                availableCapacity: { _ in 10_000_000 },
                resourceURL: { _ in root.appending(path: "lock") }
            )
            await #expect(throws: RuntimeError.installationFailed("ERROR: hash mismatch")) { try await manager.install("python") }
            let pip = commands.runs.current.first { $0.contains("pip") } ?? []
            #expect(pip.contains("--require-hashes"))
            #expect(pip.contains("--only-binary=:all:"))
        }
    }

    @Test
    func importsOnlyGGUFFiles() async throws {
        try await withRoot { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let valid = root.appending(path: "My Model.gguf")
            let invalid = root.appending(path: "notes.gguf")
            try Data("GGUF....".utf8).write(to: valid)
            try Data("hello".utf8).write(to: invalid)
            let manager = LocalRuntimeManager(manifest: Self.manifest(), root: root.appending(path: "support"), availableCapacity: { _ in 10_000_000 })

            let imported = try await manager.importModel(from: valid, projector: nil)
            #expect(imported.id == "imported-my-model")
            #expect(await manager.importedModels().map(\.id) == ["imported-my-model"])
            #expect(try await manager.modelFiles(for: imported.id).model.lastPathComponent == "My Model.gguf")
            await #expect(throws: RuntimeError.self) { try await manager.importModel(from: invalid, projector: nil) }
        }
    }

    @Test
    func bundledManifestPinsEveryComponent() throws {
        let manifest = try RuntimeManifest.bundled()
        let checksums = manifest.runtimes.map(\.archive.sha256)
            + (manifest.decisionModels + manifest.languageModels).flatMap { $0.files.compactMap { $0.sha256 ?? $0.gitBlobSHA1 } }

        #expect(manifest.runtime("python") != nil)
        #expect(manifest.runtime("llama.cpp")?.executable == "llama-server")
        #expect(manifest.model("laya-multilingual")?.contextLimit == 1_024)
        #expect(manifest.model(AIAgentSettings.defaultLocalModelID)?.files.contains { $0.role == .visionProjector } == true)
        let verified = manifest.model(AIAgentSettings.defaultLocalModelID)?.verifiedWith?.first
        #expect(verified?.version == manifest.runtime("llama.cpp")?.version)
        #expect(verified?.toolCalls == true && verified?.vision == true)
        #expect((manifest.decisionModels + manifest.languageModels).allSatisfy { $0.revision.count == 40 && !$0.license.isEmpty })
        #expect(checksums.allSatisfy { $0.count == 64 || $0.count == 40 })
    }

    @Test
    func fileDigestsMatchGitAndSHA256() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("hello\n".utf8).write(to: url)

        #expect(try FileDigest.sha256(of: url) == "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
        #expect(try FileDigest.gitBlobSHA1(of: url) == "ce013625030ba8dba906f756967f9e9ca394464a")
    }
}

final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let secrets = Locked<[CredentialAccount: String]>([:])

    func secret(for account: CredentialAccount) throws -> String? { secrets.current[account] }
    func setSecret(_ secret: String, for account: CredentialAccount) throws { secrets.withValue { $0[account] = secret } }
    func removeSecret(for account: CredentialAccount) throws { secrets.withValue { $0[account] = nil } }
}

struct CredentialAndSettingsTests {
    @Test
    func keychainStoresReplacesAndRemovesSecrets() throws {
        let store = KeychainCredentialStore(service: "dev.paugarcia32.PulseNotch.Tests.\(UUID().uuidString)")
        defer { try? store.removeSecret(for: .openRouter) }

        #expect(try store.secret(for: .openRouter) == nil)
        try store.setSecret("first", for: .openRouter)
        try store.setSecret("second", for: .openRouter)
        #expect(try store.secret(for: .openRouter) == "second")
        try store.removeSecret(for: .openRouter)
        #expect(try store.secret(for: .openRouter) == nil)
    }

    @Test
    func settingsFromOlderVersionsKeepDefaultsForNewFields() throws {
        let data = Data(#"{"decisionKind":"managedLaya","languageKind":"localEndpoint","localEndpointModel":"mimo"}"#.utf8)
        let settings = try JSONDecoder().decode(AIAgentSettings.self, from: data)

        #expect(settings.decisionKind == .managedLaya)
        #expect(settings.localEndpointModel == "mimo")
        #expect(settings.retentionDays == 30)
        #expect(settings.limits == .default)
        #expect(!settings.computerUseEnabled)
    }

    @Test
    func settingsNeverPersistCredentials() throws {
        let suite = "PulseNotchTests.\(#function)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AIAgentSettings()
        settings.openRouterModel = "a/b"
        AIAgentSettingsStore(defaults: defaults).save(settings)

        let stored = String(decoding: try #require(defaults.data(forKey: "settings.aiAgent")), as: UTF8.self)
        #expect(!stored.localizedCaseInsensitiveContains("key"))
        #expect(AIAgentSettingsStore(defaults: defaults).load().openRouterModel == "a/b")
    }

    @Test
    func setupIssuesNameMissingCredentialsForHostedProvidersOnly() {
        var hosted = AIAgentSettings()
        hosted.decisionKind = .jev
        hosted.languageKind = .openRouter
        #expect(hosted.setupIssues { _ in false } == [
            "Add a TypeSafe API key for JEV.",
            "Add an OpenRouter API key.",
            "Choose an OpenRouter model."
        ])

        var local = AIAgentSettings()
        local.decisionKind = .managedLaya
        local.languageKind = .managedLocal
        #expect(local.setupIssues { _ in false }.isEmpty)
        #expect(local.configuration().isFullyLocalInference)
        #expect(!local.usesHostedProvider)
    }

    @Test
    func computerUseRequiresAVerifiedToolCallingModel() {
        var settings = AIAgentSettings()
        settings.computerUseEnabled = true
        #expect(!settings.configuration().computerUseEnabled)

        settings.capabilityReports[settings.capabilityKey] = CapabilityReport(modelID: "", toolCallsVerified: true, visionVerified: false, detail: "")
        #expect(settings.configuration().computerUseEnabled)
        #expect(!settings.configuration().visionVerified)
    }
}
