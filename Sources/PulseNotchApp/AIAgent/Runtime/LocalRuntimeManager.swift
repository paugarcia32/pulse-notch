import Foundation

enum ComponentState: Hashable, Sendable {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case verifying
    case installing(String)
    case installed(version: String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .installing: true
        case .notInstalled, .installed, .failed: false
        }
    }

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

/// A GGUF model the user imported instead of downloading from the catalog.
struct ImportedModel: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let modelPath: String
    let projectorPath: String?
    let size: Int64
}

private struct InstallReceipt: Codable {
    let id: String
    let version: String
    let executable: String?
}

/// Installs, verifies, reuses, and removes optional local runtimes and models under
/// Pulse Notch's Application Support directory. Downloads start only on request.
actor LocalRuntimeManager {
    let manifest: RuntimeManifest
    let root: URL
    private let downloader: any FileDownloading
    private let commands: any CommandRunning
    private let availableCapacity: @Sendable (URL) -> Int64?
    private let resourceURL: @Sendable (String) -> URL?
    private let onStateChange: @Sendable (String, ComponentState) -> Void
    private var states: [String: ComponentState] = [:]

    init(
        manifest: RuntimeManifest,
        root: URL = LocalRuntimeManager.defaultRoot(),
        downloader: any FileDownloading = URLSessionFileDownloader(),
        commands: any CommandRunning = ProcessCommandRunner(),
        availableCapacity: @escaping @Sendable (URL) -> Int64? = LocalRuntimeManager.availableCapacity,
        resourceURL: @escaping @Sendable (String) -> URL? = { name in
            let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
            return Bundle.module.url(forResource: parts.first, withExtension: parts.count > 1 ? parts[1] : nil)
        },
        onStateChange: @escaping @Sendable (String, ComponentState) -> Void = { _, _ in }
    ) {
        self.manifest = manifest
        self.root = root
        self.downloader = downloader
        self.commands = commands
        self.availableCapacity = availableCapacity
        self.resourceURL = resourceURL
        self.onStateChange = onStateChange
    }

    static func defaultRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Pulse Notch/AIAgent", directoryHint: .isDirectory)
    }

    @Sendable static func availableCapacity(at url: URL) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: State

    func state(of id: String) -> ComponentState {
        if let state = states[id], state.isBusy { return state }
        if let receipt = receipt(for: id) { return .installed(version: receipt.version) }
        return states[id] ?? .notInstalled
    }

    func allStates() -> [String: ComponentState] {
        let ids = manifest.runtimes.map(\.id) + manifest.decisionModels.map(\.id) + manifest.languageModels.map(\.id)
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, state(of: $0)) })
    }

    private func set(_ id: String, _ state: ComponentState) {
        states[id] = state
        onStateChange(id, state)
    }

    // MARK: Paths

    func directory(for id: String) -> URL {
        let group = manifest.runtime(id) != nil ? "runtimes" : "models"
        return root.appending(path: "\(group)/\(id)", directoryHint: .isDirectory)
    }

    var pythonExecutable: URL { directory(for: "python").appending(path: "venv/bin/python3") }

    func layaHelperScript() throws -> URL {
        guard let url = resourceURL("laya_helper.py") else { throw RuntimeError.manifestMissing }
        return url
    }

    func llamaServerExecutable() throws -> URL {
        guard let receipt = receipt(for: "llama.cpp"), let executable = receipt.executable else {
            throw RuntimeError.notInstalled("llama.cpp")
        }
        return directory(for: "llama.cpp").appending(path: executable)
    }

    func modelFiles(for id: String) throws -> (model: URL, projector: URL?) {
        if let imported = importedModels().first(where: { $0.id == id }) {
            return (URL(fileURLWithPath: imported.modelPath), imported.projectorPath.map(URL.init(fileURLWithPath:)))
        }
        guard let model = manifest.model(id), receipt(for: id) != nil else { throw RuntimeError.notInstalled(id) }
        let directory = directory(for: id)
        guard let main = model.files.first(where: { $0.role == .model }) ?? model.files.first else {
            throw RuntimeError.notInstalled(id)
        }
        let projector = model.files.first { $0.role == .visionProjector }
        return (directory.appending(path: main.path), projector.map { directory.appending(path: $0.path) })
    }

    // MARK: Install

    /// Installs a runtime or model. Existing verified installations are reused offline.
    func install(_ id: String) async throws {
        if case .installed = state(of: id) { return }
        guard !(states[id]?.isBusy ?? false) else { return }
        do {
            if let runtime = manifest.runtime(id) {
                try await install(runtime)
            } else if let model = manifest.model(id) {
                if case .installed = state(of: model.runtime) {} else { try await install(model.runtime) }
                try await install(model)
            } else {
                throw RuntimeError.notInstalled(id)
            }
        } catch is CancellationError {
            set(id, .notInstalled)
            throw CancellationError()
        } catch let error as RuntimeError {
            set(id, .failed(error.userMessage))
            throw error
        } catch {
            set(id, .failed(error.localizedDescription))
            throw error
        }
    }

    private func install(_ runtime: RuntimeManifest.Runtime) async throws {
        try checkSystem(runtime)
        try checkDiskSpace(runtime.installedSize)
        let destination = directory(for: runtime.id)
        let archive = root.appending(path: "downloads/\(runtime.id)-\(runtime.version).tar.gz")
        try await download(runtime.archive.url, to: archive, size: runtime.archive.size, id: runtime.id)
        set(runtime.id, .verifying)
        try verify(archive, sha256: runtime.archive.sha256, name: runtime.name)

        set(runtime.id, .installing("Extracting"))
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await check(commands.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", destination.path], environment: [:]))

        var executable: String?
        if let packages = runtime.packages {
            try await installPythonPackages(packages, in: destination, runtimeID: runtime.id)
        }
        if let name = runtime.executable {
            guard let found = Self.find(named: name, under: destination) else {
                throw RuntimeError.installationFailed("\(name) was not found in the archive.")
            }
            executable = String(found.path.dropFirst(destination.path.count + 1))
        }
        try writeReceipt(InstallReceipt(id: runtime.id, version: runtime.version, executable: executable), for: runtime.id)
        try? FileManager.default.removeItem(at: archive)
        set(runtime.id, .installed(version: runtime.version))
    }

    private func installPythonPackages(_ packages: RuntimeManifest.Packages, in destination: URL, runtimeID: String) async throws {
        guard let lockFile = resourceURL(packages.lockFile) else { throw RuntimeError.manifestMissing }
        let basePython = destination.appending(path: "python/bin/python3")
        set(runtimeID, .installing("Creating environment"))
        try await check(commands.run(basePython, ["-m", "venv", destination.appending(path: "venv").path], environment: [:]))
        set(runtimeID, .installing("Installing \(packages.requirement)"))
        try await check(commands.run(
            destination.appending(path: "venv/bin/python3"),
            [
                "-m", "pip", "install",
                "--require-hashes", "--only-binary=:all:", "--no-input", "--disable-pip-version-check",
                "-r", lockFile.path
            ],
            environment: ["PIP_NO_CACHE_DIR": "1"]
        ))
    }

    private func install(_ model: RuntimeManifest.Model) async throws {
        try checkDiskSpace(model.downloadSize)
        let destination = directory(for: model.id)
        let total = model.downloadSize
        var completed: Int64 = 0
        for file in model.files {
            try Task.checkCancellation()
            guard let url = model.url(for: file) else { throw RuntimeError.downloadFailed("Invalid file path \(file.path)") }
            let target = destination.appending(path: file.path)
            if FileManager.default.fileExists(atPath: target.path), (try? verify(target, file: file)) != nil {
                completed += file.size
                continue
            }
            let partial = target.appendingPathExtension("partial")
            let base = completed
            let onStateChange = self.onStateChange
            let modelID = model.id
            try await downloader.download(url, to: partial, expectedSize: file.size) { received in
                onStateChange(modelID, .downloading(received: base + received, total: total))
            }
            set(model.id, .verifying)
            try verify(partial, file: file)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: partial, to: target)
            completed += file.size
            set(model.id, .downloading(received: completed, total: total))
        }
        try writeReceipt(InstallReceipt(id: model.id, version: model.revision, executable: nil), for: model.id)
        set(model.id, .installed(version: model.revision))
    }

    private func download(_ url: URL, to destination: URL, size: Int64, id: String) async throws {
        set(id, .downloading(received: 0, total: size))
        let onStateChange = self.onStateChange
        try await downloader.download(url, to: destination, expectedSize: size) { received in
            onStateChange(id, .downloading(received: received, total: size))
        }
    }

    // MARK: Remove and import

    /// Removes an installed component. Downloaded models are only removed on request.
    func remove(_ id: String) throws {
        if let imported = importedModels().first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: imported.modelPath).deletingLastPathComponent())
            set(id, .notInstalled)
            return
        }
        let directory = directory(for: id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        set(id, .notInstalled)
    }

    /// Copies a user-selected GGUF file (and optional vision projector) into the models directory.
    func importModel(from source: URL, projector: URL?) throws -> ImportedModel {
        try Self.validateGGUF(source)
        if let projector { try Self.validateGGUF(projector) }
        let name = source.deletingPathExtension().lastPathComponent
        let id = "imported-" + name.lowercased().replacingOccurrences(of: " ", with: "-")
        let directory = root.appending(path: "models/imported/\(id)", directoryHint: .isDirectory)
        let size = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64 ?? 0)
            + (projector.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64 } ?? 0)
        try checkDiskSpace(size)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let modelTarget = directory.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: modelTarget)
        var projectorTarget: URL?
        if let projector {
            let target = directory.appending(path: projector.lastPathComponent)
            try FileManager.default.copyItem(at: projector, to: target)
            projectorTarget = target
        }
        let model = ImportedModel(id: id, name: name, modelPath: modelTarget.path, projectorPath: projectorTarget?.path, size: size)
        try JSONEncoder().encode(model).write(to: directory.appending(path: ".imported.json"))
        return model
    }

    func importedModels() -> [ImportedModel] {
        let directory = root.appending(path: "models/imported", directoryHint: .isDirectory)
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { entry in
            (try? Data(contentsOf: entry.appending(path: ".imported.json"))).flatMap {
                try? JSONDecoder().decode(ImportedModel.self, from: $0)
            }
        }
        .sorted { $0.name < $1.name }
    }

    static func validateGGUF(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            throw RuntimeError.invalidModelFile("\(url.lastPathComponent) is not a GGUF file.")
        }
    }

    // MARK: Helpers

    private func checkSystem(_ runtime: RuntimeManifest.Runtime) throws {
        #if !arch(arm64)
        throw RuntimeError.unsupportedSystem("\(runtime.name) requires a Mac with Apple silicon.")
        #endif
        let parts = runtime.minimumMacOS.split(separator: ".").compactMap { Int($0) }
        let minimum = OperatingSystemVersion(majorVersion: parts.first ?? 14, minorVersion: parts.dropFirst().first ?? 0, patchVersion: 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(minimum) else {
            throw RuntimeError.unsupportedSystem("\(runtime.name) requires macOS \(runtime.minimumMacOS) or later.")
        }
    }

    private func checkDiskSpace(_ required: Int64) throws {
        guard let available = availableCapacity(root) else { return }
        let needed = required + required / 10
        guard available >= needed else { throw RuntimeError.insufficientDiskSpace(required: needed, available: available) }
    }

    private func verify(_ url: URL, sha256: String, name: String) throws {
        guard try FileDigest.sha256(of: url) == sha256.lowercased() else {
            try? FileManager.default.removeItem(at: url)
            throw RuntimeError.checksumMismatch(name)
        }
    }

    private func verify(_ url: URL, file: RuntimeManifest.ModelFile) throws {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        let matches: Bool
        if size != file.size {
            matches = false
        } else if let sha256 = file.sha256 {
            matches = try FileDigest.sha256(of: url) == sha256.lowercased()
        } else if let sha1 = file.gitBlobSHA1 {
            matches = try FileDigest.gitBlobSHA1(of: url) == sha1.lowercased()
        } else {
            matches = false
        }
        guard matches else {
            try? FileManager.default.removeItem(at: url)
            throw RuntimeError.checksumMismatch(file.path)
        }
    }

    private func check(_ result: CommandResult) throws {
        guard result.status == 0 else {
            let tail = result.output.split(separator: "\n").suffix(3).joined(separator: " ")
            throw RuntimeError.installationFailed(tail.isEmpty ? "exit status \(result.status)" : tail)
        }
    }

    private func receiptURL(for id: String) -> URL { directory(for: id).appending(path: ".receipt.json") }

    private func receipt(for id: String) -> InstallReceipt? {
        guard let data = try? Data(contentsOf: receiptURL(for: id)),
              let receipt = try? JSONDecoder().decode(InstallReceipt.self, from: data)
        else { return nil }
        let expected = manifest.runtime(id)?.version ?? manifest.model(id)?.revision
        return receipt.version == expected ? receipt : nil
    }

    private func writeReceipt(_ receipt: InstallReceipt, for id: String) throws {
        try FileManager.default.createDirectory(at: directory(for: id), withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(to: receiptURL(for: id), options: .atomic)
    }

    static func find(named name: String, under directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }
}
