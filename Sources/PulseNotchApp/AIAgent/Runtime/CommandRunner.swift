import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: String
}

protocol CommandRunning: Sendable {
    func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> CommandResult
}

/// Runs installer tools such as `tar` and `pip` with a minimal environment.
struct ProcessCommandRunner: CommandRunning {
    func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ManagedEnvironment.minimal.merging(environment) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        let collected = Locked(Data())
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            collected.withValue { buffer in
                buffer.append(data)
                // Keep only the tail; installer logs can be long.
                if buffer.count > 64 * 1024 { buffer = buffer.suffix(32 * 1024) }
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                process.terminationHandler = { process in
                    output.fileHandleForReading.readabilityHandler = nil
                    let text = String(decoding: collected.current, as: UTF8.self)
                    continuation.resume(returning: CommandResult(status: process.terminationStatus, output: text))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: RuntimeError.installationFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

enum ManagedEnvironment {
    /// Child processes do not inherit the app's environment, which could contain
    /// credentials or proxies the user did not intend for them.
    static let minimal: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8",
        "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        "TMPDIR": FileManager.default.temporaryDirectory.path
    ]
}

/// A small lock-protected box for values shared with callbacks on other threads.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    @discardableResult
    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var current: Value { withValue { $0 } }
}
