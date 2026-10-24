import Foundation
import PulseNotchCore

enum ClaudeSessionReader {
    private struct Session: Decodable {
        let pid: Int
        let sessionId: String
        let status: String?
        let cwd: String?
        let name: String?
        let startedAt: TimeInterval
        let procStart: String?
        let statusUpdatedAt: TimeInterval?
    }

    static var sessionDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions")
    }

    static func activeSessions(
        among processes: [DetectedCodingAgent],
        in directory: URL = sessionDirectory,
        at date: Date = Date()
    ) throws -> [DetectedCodingAgent] {
        try processes.filter { $0.kind == .claude }.compactMap { process in
            guard let pid = process.processID else { return nil }
            let url = directory.appending(path: "\(pid).json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            // Claude updates its registry atomically. Invalid or older schemas cannot
            // establish that work is running and must never fall back to process presence.
            do {
                let data = try Data(contentsOf: url)
                return try parse(data, process: process, at: date)
            } catch is DecodingError {
                return nil
            } catch CocoaError.fileReadNoSuchFile {
                // The process may exit and remove its entry during this poll.
                return nil
            }
        }
    }

    static func parse(
        _ data: Data,
        process: DetectedCodingAgent,
        at date: Date
    ) throws -> DetectedCodingAgent? {
        let session = try JSONDecoder().decode(Session.self, from: data)
        guard process.kind == .claude,
              session.pid == process.processID,
              session.status == "busy",
              !session.sessionId.isEmpty,
              let processStartedAt = process.startedAt else { return nil }

        // A registry file can outlive a crash and its PID can be reused. Match the
        // process incarnation, not just its number, before trusting a saved busy state.
        if let procStart = session.procStart {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
            guard let registeredStart = formatter.date(from: procStart),
                  abs(registeredStart.timeIntervalSince(processStartedAt)) <= 2 else { return nil }
        }
        let sessionStartedAt = Date(timeIntervalSince1970: session.startedAt / 1_000)
        guard sessionStartedAt >= processStartedAt.addingTimeInterval(-2),
              sessionStartedAt <= date else { return nil }
        let workStartedAt = session.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
            ?? sessionStartedAt
        guard workStartedAt >= sessionStartedAt, workStartedAt <= date else { return nil }

        let title = session.name.flatMap { $0.isEmpty ? nil : $0 } ?? process.title
        return DetectedCodingAgent(
            id: "claude-\(session.sessionId)",
            kind: .claude,
            title: title,
            workingDirectory: session.cwd,
            startedAt: workStartedAt,
            processID: session.pid
        )
    }
}
