import Foundation

public struct GitHubActionSession: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case completed(GitHubPullRequest.ActionStatus)
    }

    public let runner: GitHubPullRequest.ActionRunner
    public let detectedAt: Date
    public let status: Status

    public var id: String { runner.id }

    public init(runner: GitHubPullRequest.ActionRunner, detectedAt: Date, status: Status) {
        self.runner = runner
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
        runners: [GitHubPullRequest.ActionRunner],
        at date: Date
    ) -> [GitHubActionSession] {
        let runnersByID = Dictionary(runners.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let active = runners.filter { $0.status == .running }
        let activeByID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let previousByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var updated = active.map { runner in
            GitHubActionSession(
                runner: runner,
                detectedAt: previousByID[runner.id]?.detectedAt ?? date,
                status: .running
            )
        }

        for session in sessions where activeByID[session.id] == nil {
            switch session.status {
            case .running:
                guard let runner = runnersByID[session.id], runner.status != .running else { continue }
                updated.append(.init(runner: runner, detectedAt: session.detectedAt, status: .completed(runner.status)))
            case let .completed(status):
                guard date.timeIntervalSince(session.runner.updatedAt) < completedRetention else { continue }
                updated.append(.init(runner: session.runner, detectedAt: session.detectedAt, status: .completed(status)))
            }
        }

        sessions = updated.sorted { lhs, rhs in
            switch (lhs.status, rhs.status) {
            case (.running, .completed): true
            case (.completed, .running): false
            default: lhs.runner.updatedAt > rhs.runner.updatedAt
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
