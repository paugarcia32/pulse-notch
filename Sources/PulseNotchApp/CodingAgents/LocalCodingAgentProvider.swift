import Foundation
import PulseNotchCore

actor LocalCodingAgentProvider: CodingAgentProviding {
    private var processDirectoryCache: [Int: (String?, Date)] = [:]
    private var branchCache: [String: (String?, Date)] = [:]

    func activeAgents() throws -> [DetectedCodingAgent] {
        let date = Date()
        let processList = try CommandOutput.read(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,etime=,command="]
        )
        var agents = LocalCodingAgentProcessParser.parse(
            processList,
            at: date
        )

        if let desktopStartedAt = OpenCodeDesktopSessionReader.launchDate(
            in: processList,
            at: date
        ) {
            agents.append(contentsOf: (try? OpenCodeDesktopSessionReader.activeSessions(
                launchedAt: desktopStartedAt
            )) ?? [])
        }

        let codexSessions = (try? CodexSessionReader.activeSessions()) ?? []
        if !codexSessions.isEmpty {
            agents.removeAll { $0.kind == .codex }
            agents.append(contentsOf: codexSessions)
        }

        return agents.map { enrich($0, at: date) }
    }

    func usage() -> [CodingAgentUsageAvailability] {
        LocalCodingAgentInstallation.installedKinds.map { kind in
            do {
                let usage: CodingAgentUsage? = switch kind {
                case .codex: try CodexUsageReader.read()
                case .claude: try ClaudeUsageReader.read()
                case .antigravity: try AntigravityUsageReader.read()
                case .cursor, .opencode: nil
                }
                return usage.map(CodingAgentUsageAvailability.available)
                    ?? .unavailable(kind)
            } catch {
                return .unavailable(kind)
            }
        }
    }

    private func enrich(
        _ agent: DetectedCodingAgent,
        at date: Date
    ) -> DetectedCodingAgent {
        let directory = agent.workingDirectory
            ?? agent.processID.flatMap { workingDirectory(for: $0, at: date) }
        let branch = directory.flatMap { gitBranch(in: $0, at: date) }

        return DetectedCodingAgent(
            id: agent.id,
            kind: agent.kind,
            title: agent.title,
            workingDirectory: directory,
            gitBranch: branch,
            startedAt: agent.startedAt,
            processID: agent.processID
        )
    }

    private func workingDirectory(for processID: Int, at date: Date) -> String? {
        if let cached = processDirectoryCache[processID],
           date.timeIntervalSince(cached.1) < 30 {
            return cached.0
        }

        let output = try? CommandOutput.read(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-p", "\(processID)", "-d", "cwd", "-Fn"]
        )
        let directory = output?
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("n") })
            .map { String($0.dropFirst()) }
        processDirectoryCache[processID] = (directory, date)
        return directory
    }

    private func gitBranch(in directory: String, at date: Date) -> String? {
        if let cached = branchCache[directory], date.timeIntervalSince(cached.1) < 30 {
            return cached.0
        }

        let branch = (try? CommandOutput.read(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "branch", "--show-current"]
        ))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nonEmptyBranch = branch?.isEmpty == false ? branch : nil
        branchCache[directory] = (nonEmptyBranch, date)
        return nonEmptyBranch
    }
}

enum OpenCodeDesktopSessionReader {
    private struct ActiveSession: Decodable {
        let id: String
        let title: String
        let directory: String
        let startedAt: TimeInterval
    }

    static func launchDate(in processList: String, at date: Date) -> Date? {
        processList.split(separator: "\n").compactMap { line -> Date? in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  fields[2].hasSuffix("/OpenCode.app/Contents/MacOS/OpenCode"),
                  let elapsed = LocalCodingAgentProcessParser.elapsedDuration(String(fields[1]))
            else {
                return nil
            }
            return date.addingTimeInterval(-elapsed)
        }.first
    }

    static func activeSessions(launchedAt date: Date) throws -> [DetectedCodingAgent] {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/share/opencode/opencode.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            return []
        }

        let output = try CommandOutput.read(
            executable: "/usr/bin/sqlite3",
            arguments: ["-readonly", "-json", database.path, activeSessionsQuery(launchedAt: date)]
        )
        return try parse(output, launchedAt: date)
    }

    static func parse(_ output: String, launchedAt date: Date) throws -> [DetectedCodingAgent] {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let sessions = try JSONDecoder().decode([ActiveSession].self, from: Data(output.utf8))
        return sessions.filter {
            $0.startedAt >= date.addingTimeInterval(-2).timeIntervalSince1970 * 1_000
        }.map { session in
            DetectedCodingAgent(
                id: "opencode-\(session.id)",
                kind: .opencode,
                title: session.title,
                workingDirectory: session.directory,
                startedAt: Date(timeIntervalSince1970: session.startedAt / 1_000)
            )
        }
    }

    static func activeSessionsQuery(launchedAt date: Date) -> String {
        let earliestMessage = Int(date.addingTimeInterval(-2).timeIntervalSince1970 * 1_000)
        return """
        WITH latest_messages AS (
          SELECT m.session_id, m.data, m.time_created,
            ROW_NUMBER() OVER (
              PARTITION BY m.session_id
              ORDER BY m.time_created DESC, m.id DESC
            ) AS recency
          FROM message m
          WHERE m.time_created >= \(earliestMessage)
        )
        SELECT s.id, s.title, s.directory, m.time_created AS startedAt
        FROM latest_messages m
        JOIN session s ON s.id = m.session_id
        WHERE m.recency = 1
          AND json_extract(m.data, '$.role') = 'assistant'
          AND json_extract(m.data, '$.time.completed') IS NULL;
        """
    }
}

enum LocalCodingAgentInstallation {
    static var installedKinds: [CodingAgentKind] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        return CodingAgentKind.allCases.filter { kind in
            let executableNames: [String]
            let fixedPaths: [String]
            switch kind {
            case .codex:
                executableNames = ["codex"]
                fixedPaths = []
            case .claude:
                executableNames = ["claude"]
                fixedPaths = ["\(home)/.local/bin/claude"]
            case .cursor:
                executableNames = ["cursor-agent"]
                fixedPaths = ["\(home)/.local/bin/cursor-agent"]
            case .antigravity:
                executableNames = ["agy"]
                fixedPaths = ["\(home)/.local/bin/agy"]
            case .opencode:
                executableNames = ["opencode"]
                fixedPaths = [
                    "\(home)/.opencode/bin/opencode",
                    "\(home)/.local/bin/opencode",
                    "\(home)/bin/opencode"
                ]
            }

            return (fixedPaths + searchPaths.flatMap { directory in
                executableNames.map { "\(directory)/\($0)" }
            }).contains(where: FileManager.default.fileExists(atPath:))
        }
    }
}

enum CodingAgentProviderError: Error, Equatable {
    case commandFailed
    case commandTimedOut
}

enum CommandOutput {
    static func read(
        executable: String,
        arguments: [String],
        standardInput: String? = nil,
        timeout: TimeInterval = 5
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let input = standardInput.map { _ in Pipe() }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input

        try process.run()
        if let standardInput {
            input?.fileHandleForWriting.write(Data(standardInput.utf8))
            do {
                try input?.fileHandleForWriting.close()
            } catch {
                process.terminate()
                throw error
            }
        }
        let timeoutState = CommandTimeoutState(process: process)
        let timeoutWork = DispatchWorkItem { timeoutState.terminateProcess() }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + timeout,
            execute: timeoutWork
        )
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWork.cancel()

        guard !timeoutState.didTimeOut else {
            throw CodingAgentProviderError.commandTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw CodingAgentProviderError.commandFailed
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class CommandTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var timedOut = false

    init(process: Process) {
        self.process = process
    }

    var didTimeOut: Bool {
        lock.withLock { timedOut }
    }

    func terminateProcess() {
        lock.withLock {
            guard process.isRunning else {
                return
            }
            timedOut = true
            process.terminate()
        }
    }
}

enum LocalCodingAgentProcessParser {
    static func parse(
        _ processList: String,
        at date: Date = Date()
    ) -> [DetectedCodingAgent] {
        processList.split(separator: "\n").compactMap { line in
            let fields = line.split(
                maxSplits: 2,
                whereSeparator: \Character.isWhitespace
            )
            guard
                fields.count >= 2,
                let processID = Int(fields[0])
            else {
                return nil
            }

            let elapsed = fields.count == 3
                ? elapsedDuration(String(fields[1]))
                : nil
            let command = elapsed == nil
                ? fields.dropFirst().joined(separator: " ")
                : String(fields[2])
            guard let kind = kind(for: command) else {
                return nil
            }

            return DetectedCodingAgent(
                id: "\(kind.rawValue)-\(processID)",
                kind: kind,
                title: title(for: command),
                startedAt: elapsed.map { date.addingTimeInterval(-$0) },
                processID: processID
            )
        }
    }

    static func elapsedDuration(_ value: String) -> TimeInterval? {
        let dayAndTime = value.split(separator: "-", maxSplits: 1)
        let days = dayAndTime.count == 2 ? Double(dayAndTime[0]) : 0
        let time = dayAndTime.last?.split(separator: ":").compactMap {
            Double($0)
        } ?? []
        guard time.count == 2 || time.count == 3 else {
            return nil
        }

        let seconds = time.reversed().enumerated().reduce(0.0) { total, item in
            total + item.element * pow(60, Double(item.offset))
        }
        return days.map { $0 * 86_400 + seconds } ?? seconds
    }

    private static func kind(for command: String) -> CodingAgentKind? {
        let command = command.lowercased()
        guard !command.contains(".app/contents/") else {
            return nil
        }

        let executableName = command
            .split(whereSeparator: \Character.isWhitespace)
            .first?
            .split(separator: "/")
            .last
            .map(String.init)

        if executableName == "codex"
            || command.contains("node_modules/@openai/codex") {
            guard !command.contains(" app-server") else {
                return nil
            }
            return .codex
        }
        if executableName == "claude"
            || command.contains("@anthropic-ai/claude-code") {
            return .claude
        }
        if executableName == "cursor-agent" {
            return .cursor
        }
        if executableName == "agy" {
            guard !(command.contains("--print") && command.contains("/usage")) else {
                return nil
            }
            return .antigravity
        }
        if executableName == "opencode" {
            return .opencode
        }
        return nil
    }

    private static func title(for command: String) -> String {
        let pattern = #"--(?:title|name)(?:=|\s+)(?:\"([^\"]+)\"|'([^']+)'|(\S+))"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(
               in: command,
               range: NSRange(command.startIndex..., in: command)
           ) {
            for index in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: index), in: command) {
                    return String(command[range]).condensedAgentTitle
                }
            }
        }
        return "Active coding session"
    }
}

enum CodexSessionReader {
    private struct ActiveSession: Decodable {
        let id: String
        let workingDirectory: String?
        let startedAt: TimeInterval?
    }

    static func activeSessions() throws -> [DetectedCodingAgent] {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex")
        let database = codexDirectory.appending(path: "thread_history_1.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else {
            return []
        }

        let output = try CommandOutput.read(
            executable: "/usr/bin/sqlite3",
            arguments: ["-json", database.path, activeSessionsQuery]
        )
        let active = try JSONDecoder().decode(
            [ActiveSession].self,
            from: Data(output.utf8)
        )
        return active.map { session in
            DetectedCodingAgent(
                id: "codex-\(session.id)",
                kind: .codex,
                title: "Active coding session",
                workingDirectory: session.workingDirectory,
                startedAt: session.startedAt.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    static let activeSessionsQuery = """
        WITH latest_turns AS (
          SELECT t.*,
            ROW_NUMBER() OVER (
              PARTITION BY t.thread_id
              ORDER BY t.rollout_ordinal DESC
            ) AS recency
          FROM thread_turns t
        )
        SELECT t.thread_id AS id,
          (SELECT json_extract(i.item_json, '$.cwd')
           FROM thread_items i
           WHERE i.thread_id = t.thread_id
             AND json_extract(i.item_json, '$.cwd') IS NOT NULL
           ORDER BY i.rollout_ordinal DESC LIMIT 1) AS workingDirectory,
          t.started_at AS startedAt
        FROM latest_turns t
        WHERE t.recency = 1 AND t.status = 'inProgress';
        """

}

private extension String {
    var condensedAgentTitle: String {
        let title = split(separator: "\n", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard !title.isEmpty else {
            return "Active coding session"
        }
        return title.count > 64 ? String(title.prefix(63)) + "…" : title
    }
}
