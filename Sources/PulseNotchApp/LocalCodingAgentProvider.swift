import Foundation
import PulseNotchCore

actor LocalCodingAgentProvider: CodingAgentProviding {
    private var processDirectoryCache: [Int: (String?, Date)] = [:]
    private var branchCache: [String: (String?, Date)] = [:]

    func activeAgents() throws -> [DetectedCodingAgent] {
        let date = Date()
        var agents = LocalCodingAgentProcessParser.parse(
            try CommandOutput.read(
                executable: "/bin/ps",
                arguments: ["-axo", "pid=,etime=,command="]
            ),
            at: date
        )

        let codexSessions = (try? CodexSessionReader.activeSessions()) ?? []
        if !codexSessions.isEmpty {
            agents.removeAll { $0.kind == .codex }
            agents.append(contentsOf: codexSessions)
        }

        return agents.map { enrich($0, at: date) }
    }

    func usage() throws -> [CodingAgentUsage] {
        var usages = LocalCodingAgentInstallation.installedKinds.map {
            CodingAgentUsage(kind: $0, windows: [])
        }

        if let index = usages.firstIndex(where: { $0.kind == .codex }),
           let codexUsage = try? CodexUsageReader.read() {
            usages[index] = codexUsage
        }
        if let index = usages.firstIndex(where: { $0.kind == .claude }),
           let claudeUsage = try? ClaudeUsageReader.read() {
            usages[index] = claudeUsage
        }
        if let index = usages.firstIndex(where: { $0.kind == .antigravity }),
           let antigravityUsage = try? AntigravityUsageReader.read() {
            usages[index] = antigravityUsage
        }
        return usages
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

enum CodingAgentProviderError: Error {
    case commandFailed
}

enum CommandOutput {
    static func read(
        executable: String,
        arguments: [String]
    ) throws -> String {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CodingAgentProviderError.commandFailed
        }
        return String(decoding: data, as: UTF8.self)
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
        let fallbackTitle: String?
        let workingDirectory: String?
        let startedAt: TimeInterval?
    }

    private struct SessionIndexEntry: Decodable {
        let id: String
        let threadName: String

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
        }
    }

    static func activeSessions() throws -> [DetectedCodingAgent] {
        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex")
        let database = codexDirectory.appending(path: "thread_history_1.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else {
            return []
        }

        let query = """
        SELECT DISTINCT t.thread_id AS id,
          (SELECT json_extract(i.item_json, '$.content[0].text')
           FROM thread_items i
           WHERE i.thread_id = t.thread_id AND i.item_type = 'userMessage'
           ORDER BY i.rollout_ordinal LIMIT 1) AS fallbackTitle,
          (SELECT json_extract(i.item_json, '$.cwd')
           FROM thread_items i
           WHERE i.thread_id = t.thread_id
             AND json_extract(i.item_json, '$.cwd') IS NOT NULL
           ORDER BY i.rollout_ordinal DESC LIMIT 1) AS workingDirectory,
          MIN(t.started_at) AS startedAt
        FROM thread_turns t
        WHERE t.status = 'inProgress';
        """
        let output = try CommandOutput.read(
            executable: "/usr/bin/sqlite3",
            arguments: ["-json", database.path, query]
        )
        let active = try JSONDecoder().decode(
            [ActiveSession].self,
            from: Data(output.utf8)
        )
        let titles = sessionTitles(
            at: codexDirectory.appending(path: "session_index.jsonl")
        )

        return active.map { session in
            DetectedCodingAgent(
                id: "codex-\(session.id)",
                kind: .codex,
                title: (titles[session.id] ?? session.fallbackTitle
                    ?? "Active coding session").condensedAgentTitle,
                workingDirectory: session.workingDirectory,
                startedAt: session.startedAt.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    private static func sessionTitles(at url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }

        let decoder = JSONDecoder()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? decoder.decode(
                SessionIndexEntry.self,
                from: Data($0.utf8)
            ) }
            .reduce(into: [:]) { titles, entry in
                titles[entry.id] = entry.threadName
            }
    }
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
