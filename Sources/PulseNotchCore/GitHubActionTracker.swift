import Foundation

public struct GitHubActionSession: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case completed(GitHubPullRequest.ActionStatus)
    }

    public let run: GitHubActionRun
    public let detectedAt: Date
    public let status: Status

    public var id: String { run.id }

    public init(run: GitHubActionRun, detectedAt: Date, status: Status) {
        self.run = run
        self.detectedAt = detectedAt
        self.status = status
    }
}

public struct GitHubActionTracker: Sendable {
    public private(set) var sessions: [GitHubActionSession] = []
    private let completedRetention: TimeInterval
    private var acknowledgedCompletionIDs: Set<String> = []

    public var notificationSessions: [GitHubActionSession] {
        sessions.filter {
            if case .completed = $0.status {
                !acknowledgedCompletionIDs.contains($0.id)
            } else {
                true
            }
        }
    }

    public init(completedRetention: TimeInterval = 5 * 60) {
        self.completedRetention = completedRetention
    }

    @discardableResult
    public mutating func update(
        runs: [GitHubActionRun],
        at date: Date
    ) -> [GitHubActionSession] {
        let runsByID = Dictionary(runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let active = runs.filter { $0.status == .running }
        let activeByID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let previousByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var updated = active.map { run in
            GitHubActionSession(
                run: run,
                detectedAt: previousByID[run.id]?.detectedAt ?? date,
                status: .running
            )
        }

        for session in sessions where activeByID[session.id] == nil {
            switch session.status {
            case .running:
                guard let run = runsByID[session.id], run.status != .running else { continue }
                updated.append(.init(run: run, detectedAt: session.detectedAt, status: .completed(run.status)))
            case let .completed(status):
                guard date.timeIntervalSince(session.run.updatedAt) < completedRetention else { continue }
                updated.append(.init(run: session.run, detectedAt: session.detectedAt, status: .completed(status)))
            }
        }

        sessions = updated.sorted { lhs, rhs in
            switch (lhs.status, rhs.status) {
            case (.running, .completed): true
            case (.completed, .running): false
            default: lhs.run.updatedAt > rhs.run.updatedAt
            }
        }
        acknowledgedCompletionIDs.formIntersection(Set(sessions.compactMap {
            if case .completed = $0.status { $0.id } else { nil }
        }))
        return sessions
    }

    @discardableResult
    public mutating func acknowledgeCompletedSessions() -> Bool {
        let previousCount = acknowledgedCompletionIDs.count
        acknowledgedCompletionIDs.formUnion(sessions.compactMap {
            if case .completed = $0.status { $0.id } else { nil }
        })
        return previousCount != acknowledgedCompletionIDs.count
    }
}
