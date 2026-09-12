import Darwin
import Foundation
import PulseNotchCore

enum CodexUsageReader {
    private enum ReaderError: Error {
        case executableNotFound
        case serverError
        case unexpectedEndOfStream
    }

    private struct Response: Decodable {
        let id: Int?
        let result: ResultPayload?
        let error: ErrorPayload?
    }

    private struct ResultPayload: Decodable {
        let rateLimits: RateLimits?
    }

    private struct ErrorPayload: Decodable {}

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: TimeInterval?

        var usageWindow: CodingAgentUsage.Window {
            CodingAgentUsage.Window(
                durationMinutes: windowDurationMins,
                usedPercent: usedPercent,
                resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    static func read() throws -> CodingAgentUsage? {
        let process = Process()
        let input = Pipe()
        let output = Pipe()

        guard let executable = codexExecutable() else {
            throw ReaderError.executableNotFound
        }

        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        let lines = JSONLineReader(output.fileHandleForReading)
        try send(
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "pulse_notch",
                        "title": "Pulse Notch",
                        "version": "0.1.0"
                    ]
                ]
            ],
            to: input.fileHandleForWriting
        )
        _ = try response(withID: 1, from: lines)

        try send(
            ["method": "initialized", "params": [:]],
            to: input.fileHandleForWriting
        )
        try send(
            ["method": "account/rateLimits/read", "id": 2],
            to: input.fileHandleForWriting
        )

        guard let limits = try response(withID: 2, from: lines).result?.rateLimits else {
            return nil
        }

        return CodingAgentUsage(
            kind: .codex,
            windows: [limits.primary, limits.secondary]
                .compactMap { $0?.usageWindow }
        )
    }

    static func decodeRateLimits(_ data: Data) throws -> CodingAgentUsage? {
        guard let limits = try JSONDecoder().decode(Response.self, from: data)
            .result?.rateLimits else {
            return nil
        }

        return CodingAgentUsage(
            kind: .codex,
            windows: [limits.primary, limits.secondary]
                .compactMap { $0?.usageWindow }
        )
    }

    private static func response(
        withID id: Int,
        from lines: JSONLineReader
    ) throws -> Response {
        while let data = try lines.next() {
            guard let response = try? JSONDecoder().decode(Response.self, from: data),
                  response.id == id else {
                continue
            }
            guard response.error == nil else {
                throw ReaderError.serverError
            }
            return response
        }
        throw ReaderError.unexpectedEndOfStream
    }

    private static func send(
        _ object: [String: Any],
        to handle: FileHandle
    ) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func codexExecutable() -> URL? {
        let fileManager = FileManager.default
        var paths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            fileManager.homeDirectoryForCurrentUser
                .appending(path: ".local/bin/codex").path
        ]
        paths.append(contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "codex").path })

        return paths.first(where: fileManager.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}

private final class JSONLineReader {
    private enum ReaderError: Error {
        case timedOut
    }

    private let handle: FileHandle
    private var buffer = Data()

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func next() throws -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                return Data(line)
            }

            var descriptor = pollfd(
                fd: handle.fileDescriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            guard Darwin.poll(&descriptor, 1, 5_000) > 0 else {
                throw ReaderError.timedOut
            }

            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                defer { buffer.removeAll() }
                return buffer.isEmpty ? nil : buffer
            }
            buffer.append(chunk)
        }
    }
}
