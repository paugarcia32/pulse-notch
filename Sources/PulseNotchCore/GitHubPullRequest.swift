import Foundation

public struct GitHubPullRequest: Identifiable, Equatable, Sendable {
    public enum ReviewStatus: Equatable, Sendable {
        case approved
        case changesRequested
        case awaitingReview
    }

    public typealias ActionStatus = GitHubActionRun.Status

    public let id: String
    public let repository: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let reviewStatus: ReviewStatus
    public let commentCount: Int
    public let passedCheckCount: Int
    public let actionStatus: ActionStatus
    public let actionRuns: [GitHubActionRun]

    public init(
        id: String,
        repository: String,
        number: Int,
        title: String,
        url: URL,
        isDraft: Bool,
        reviewStatus: ReviewStatus,
        commentCount: Int = 0,
        passedCheckCount: Int = 0,
        actionStatus: ActionStatus = .none,
        actionRuns: [GitHubActionRun] = []
    ) {
        self.id = id
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.reviewStatus = reviewStatus
        self.commentCount = commentCount
        self.passedCheckCount = passedCheckCount
        self.actionStatus = actionStatus
        self.actionRuns = actionRuns
    }
}

public enum GitHubActionSummary {
    public struct Check: Equatable, Sendable {
        public let status: String
        public let conclusion: String?
        public let completedAt: Date?

        public init(status: String, conclusion: String? = nil, completedAt: Date? = nil) {
            self.status = status
            self.conclusion = conclusion
            self.completedAt = completedAt
        }
    }

    public static func status(for checks: [Check]) -> GitHubPullRequest.ActionStatus {
        guard !checks.isEmpty else { return .none }
        if checks.contains(where: { ["QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED"].contains($0.status.uppercased()) }) {
            return .running
        }
        if checks.contains(where: { ["FAILURE", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED", "STALE"].contains($0.conclusion?.uppercased() ?? "") }) {
            return .failed
        }
        return .succeeded(completedAt: checks.compactMap(\.completedAt).max())
    }
}
