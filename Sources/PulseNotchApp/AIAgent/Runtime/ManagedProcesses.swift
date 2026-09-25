import Darwin
import Foundation
import PulseNotchCore

/// A running local language-model server bound to loopback.
struct LocalServerEndpoint: Hashable, Sendable {
    let baseURL: URL
    /// Generated for each launch so other local processes cannot use the server.
    let apiKey: String
}

/// Owns the managed `llama.cpp` server's lifecycle. It stops when the agent is
/// disabled or Pulse Notch quits, and never outlives the app.
actor ManagedLlamaServer {
    private var process: Process?
    private var endpoint: LocalServerEndpoint?
    private var runningModelID: String?
    private var keyDirectory: URL?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isRunning: Bool { process?.isRunning == true }

    /// Starts the server for `modelID`, reusing it when that model is already loaded.
    func start(
        executable: URL,
        modelID: String,
        model: URL,
        projector: URL?,
        contextLength: Int
    ) async throws -> LocalServerEndpoint {
        if let endpoint, runningModelID == modelID, process?.isRunning == true { return endpoint }
        stop()

        let port = try Self.freeLoopbackPort()
        let apiKey = Self.randomKey()
        let directory = FileManager.default.temporaryDirectory.appending(path: "PulseNotch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let keyFile = directory.appending(path: "api-key")
        guard FileManager.default.createFile(atPath: keyFile.path, contents: Data(apiKey.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw RuntimeError.launchFailed("The server key could not be written.")
        }

        var arguments = [
            "-m", model.path,
            "--host", "127.0.0.1",
            "--port", String(port),
            "--api-key-file", keyFile.path,
            "--jinja",
            "-c", String(contextLength),
            "-ngl", "99"
        ]
        if let projector { arguments += ["--mmproj", projector.path] }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ManagedEnvironment.minimal
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw RuntimeError.launchFailed(error.localizedDescription)
        }
        self.process = process
        self.keyDirectory = directory
        guard let baseURL = URL(string: "http://127.0.0.1:\(port)/v1") else {
            stop()
            throw RuntimeError.launchFailed("Invalid server address.")
        }
        let endpoint = LocalServerEndpoint(baseURL: baseURL, apiKey: apiKey)
        do {
            try await waitUntilHealthy(port: port, process: process)
        } catch {
            stop()
            throw error
        }
        self.endpoint = endpoint
        self.runningModelID = modelID
        return endpoint
    }

    func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        endpoint = nil
        runningModelID = nil
        if let keyDirectory { try? FileManager.default.removeItem(at: keyDirectory) }
        keyDirectory = nil
    }

    private func waitUntilHealthy(port: Int, process: Process) async throws {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
        for _ in 0..<600 {
            try Task.checkCancellation()
            guard process.isRunning else {
                throw RuntimeError.launchFailed("The server exited while loading the model (status \(process.terminationStatus)).")
            }
            if let (_, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 2)),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw RuntimeError.launchFailed("The model did not finish loading within five minutes.")
    }

    static func freeLoopbackPort() throws -> Int {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw RuntimeError.launchFailed("No local port is available.") }
        defer { close(socketFD) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, length) == 0 && getsockname(socketFD, $0, &length) == 0 }
        }
        guard bound else { throw RuntimeError.launchFailed("No local port is available.") }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    static func randomKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Exchanges newline-delimited JSON with the Laya helper. Requests carry an `id`
/// that the matching response echoes.
protocol LayaHelperTransport: Sendable {
    /// - Parameter request: A JSON object without the protocol version or id.
    /// - Returns: The helper's JSON response line.
    func exchange(_ request: Data, id: String) async throws -> Data
}

/// Runs `laya_helper.py` in the managed Python environment with private pipes.
actor LayaHelperProcess: LayaHelperTransport {
    static let protocolVersion = 1

    private let python: URL
    private let script: URL
    private let checkpoint: URL
    private var process: Process?
    private var input: FileHandle?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var ready: CheckedContinuation<Void, Error>?
    private var isReady = false
    private var reader: Task<Void, Never>?

    init(python: URL, script: URL, checkpoint: URL) {
        self.python = python
        self.script = script
        self.checkpoint = checkpoint
    }

    var isRunning: Bool { process?.isRunning == true && isReady }

    func start() async throws {
        if isRunning { return }
        stop()
        let process = Process()
        process.executableURL = python
        process.arguments = ["-I", script.path, checkpoint.path]
        process.environment = ManagedEnvironment.minimal.merging([
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "PYTHONUNBUFFERED": "1",
            "PYTHONDONTWRITEBYTECODE": "1"
        ]) { _, new in new }
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let (lines, continuation) = AsyncStream.makeStream(of: Data.self)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        process.terminationHandler = { _ in continuation.finish() }
        do {
            try process.run()
        } catch {
            throw RuntimeError.launchFailed(error.localizedDescription)
        }
        self.process = process
        self.input = stdin.fileHandleForWriting
        reader = Task { [weak self] in
            var buffer = Data()
            for await chunk in lines {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    await self?.receive(Data(line))
                }
            }
            await self?.helperExited()
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    ready = continuation
                }
            }
        } onCancel: {
            Task { await self.stop() }
        }
    }

    func stop() {
        reader?.cancel()
        reader = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        try? input?.close()
        input = nil
        isReady = false
        failAll(CancellationError())
    }

    func exchange(_ request: Data, id: String) async throws -> Data {
        if !isRunning { try await start() }
        guard let input else { throw DecisionProviderError.unavailable("The Laya helper is not running.") }
        guard var message = try JSONSerialization.jsonObject(with: request) as? [String: Any] else {
            throw DecisionProviderError.malformedResponse("The Laya request is not a JSON object.")
        }
        message["v"] = Self.protocolVersion
        message["id"] = id
        let data = try JSONSerialization.data(withJSONObject: message) + Data([0x0A])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending[id] = continuation
                do {
                    try input.write(contentsOf: data)
                } catch {
                    pending[id] = nil
                    continuation.resume(throwing: DecisionProviderError.unavailable("The Laya helper stopped responding."))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: String) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func receive(_ line: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        let id = message["id"] as? String
        if id == "ready" {
            if message["ok"] as? Bool == true {
                isReady = true
                ready?.resume()
            } else {
                ready?.resume(throwing: RuntimeError.launchFailed(message["error"] as? String ?? "Laya could not load."))
            }
            ready = nil
            return
        }
        guard let id, let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: line)
    }

    private func helperExited() {
        isReady = false
        process = nil
        failAll(DecisionProviderError.unavailable("The Laya helper exited."))
    }

    private func failAll(_ error: Error) {
        ready?.resume(throwing: error)
        ready = nil
        let waiting = pending
        pending.removeAll()
        waiting.values.forEach { $0.resume(throwing: error) }
    }
}

/// Laya running on this Mac through the managed helper.
struct ManagedLayaDecisionProvider: DecisionProvider {
    let transport: any LayaHelperTransport
    let checkpoint: String
    let contextLimit: Int

    var metadata: DecisionProviderMetadata {
        DecisionProviderMetadata(provider: "Laya", model: checkpoint, isLocal: true)
    }

    func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        var body = try SystemOneWire.body(for: request, model: checkpoint)
        body.removeValue(forKey: "model")
        let line = try await transport.exchange(JSONSerialization.data(withJSONObject: body), id: UUID().uuidString)
        guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw DecisionProviderError.malformedResponse("The Laya helper returned invalid JSON.")
        }
        guard response["ok"] as? Bool == true, let result = response["result"] else {
            throw DecisionProviderError.unavailable(response["error"] as? String ?? "Laya did not answer.")
        }
        let decoded = try SystemOneWire.decodeAnswers(result, for: request)
        return DecisionResponse(
            answers: decoded.answers,
            metadata: DecisionProviderMetadata(
                provider: "Laya",
                model: decoded.model ?? checkpoint,
                isLocal: true,
                inputTokens: decoded.inputTokens
            )
        )
    }
}
