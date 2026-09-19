import Foundation

public struct GitHubRepository: Identifiable, Codable, Hashable, Sendable {
    public let nameWithOwner: String

    public var id: String { nameWithOwner.lowercased() }

    public init?(nameWithOwner: String) {
        let value = nameWithOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ Self.isValidNamePart($0) }) else { return nil }
        self.nameWithOwner = value
    }

    private static func isValidNamePart(_ part: Substring) -> Bool {
        !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || ".-_".contains($0) }
    }
}

public struct GitHubActionRun: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case none
        case running
        case failed
        case succeeded(completedAt: Date?)
    }

    public let id: String
    public let repository: String
    public let name: String
    public let event: String?
    public let ref: String?
    public let url: URL?
    public let pullRequestNumber: Int?
    public let updatedAt: Date
    public let status: Status

    public init(
        id: String,
        repository: String,
        name: String,
        event: String? = nil,
        ref: String? = nil,
        url: URL? = nil,
        pullRequestNumber: Int? = nil,
        updatedAt: Date,
        status: Status
    ) {
        self.id = id
        self.repository = repository
        self.name = name
        self.event = event
        self.ref = ref
        self.url = url
        self.pullRequestNumber = pullRequestNumber
        self.updatedAt = updatedAt
        self.status = status
    }
}

public struct GitHubActivitySnapshot: Equatable, Sendable {
    public let pullRequests: [GitHubPullRequest]
    public let actionRuns: [GitHubActionRun]

    public init(pullRequests: [GitHubPullRequest], actionRuns: [GitHubActionRun]) {
        self.pullRequests = pullRequests
        self.actionRuns = actionRuns
    }
}

public protocol GitHubActivityProviding: Sendable {
    func activity(repositories: [GitHubRepository]) async throws -> GitHubActivitySnapshot
}
