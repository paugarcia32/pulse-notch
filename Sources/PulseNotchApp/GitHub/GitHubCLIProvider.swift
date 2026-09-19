import Foundation
import PulseNotchCore

enum GitHubCLIProviderError: Error, Equatable {
    case executableNotFound
}

actor GitHubCLIProvider: GitHubActivityProviding {
    private let executableURL: URL?

    init(executableURL: URL? = GitHubCLIExecutable.locate()) {
        self.executableURL = executableURL
    }

    func activity(repositories: [GitHubRepository]) throws -> GitHubActivitySnapshot {
        guard let executableURL else { throw GitHubCLIProviderError.executableNotFound }
        let pullRequests = try pullRequests(using: executableURL)
        let selectedRepositoryIDs = Set(repositories.map(\.id))
        let pullRequestRuns = pullRequests
            .filter { !selectedRepositoryIDs.contains($0.repository.lowercased()) }
            .flatMap(\.actionRuns)
        let repositoryRuns = try repositories.flatMap { try actionRuns(in: $0, using: executableURL) }
        return GitHubActivitySnapshot(
            pullRequests: pullRequests,
            actionRuns: pullRequestRuns + repositoryRuns
        )
    }

    private func pullRequests(using executableURL: URL) throws -> [GitHubPullRequest] {
        let output = try CommandOutput.read(
            executable: executableURL.path,
            arguments: ["api", "graphql", "-f", "query=\(query)"],
            timeout: 15
        )
        return try JSONDecoder.github.decode(Response.self, from: Data(output.utf8)).data.search.nodes.map(\.pullRequest)
    }

    private func actionRuns(
        in repository: GitHubRepository,
        using executableURL: URL
    ) throws -> [GitHubActionRun] {
        let output = try CommandOutput.read(
            executable: executableURL.path,
            arguments: [
                "run", "list",
                "--repo", repository.nameWithOwner,
                "--limit", "20",
                "--json", "databaseId,workflowName,displayTitle,event,headBranch,status,conclusion,updatedAt,url"
            ],
            timeout: 15
        )
        return try JSONDecoder.github.decode([GitHubCLIWorkflowRun].self, from: Data(output.utf8))
            .map { $0.actionRun(repository: repository) }
    }

    private var query: String {
        """
        query {
          search(first: 100, query: "is:pr is:open author:@me", type: ISSUE) {
            nodes {
              ... on PullRequest {
                id number title url isDraft reviewDecision comments { totalCount }
                repository { nameWithOwner }
                statusCheckRollup {
                  contexts(first: 100) {
                    nodes {
                      __typename
                      ... on CheckRun {
                        id name status conclusion completedAt
                        checkSuite { app { slug } workflowRun { id displayTitle updatedAt workflow { name } } }
                      }
                      ... on StatusContext { state }
                    }
                  }
                }
              }
            }
          }
        }
        """
    }
}

private struct Response: Decodable {
    let data: DataContainer

    struct DataContainer: Decodable {
        let search: Search
    }

    struct Search: Decodable {
        let nodes: [PullRequestNode]
    }

    struct PullRequestNode: Decodable {
        let id: String
        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let reviewDecision: String?
        let comments: Comments
        let repository: Repository
        let statusCheckRollup: Rollup?

        var pullRequest: GitHubPullRequest {
            GitHubPullRequest(
                id: id,
                repository: repository.nameWithOwner,
                number: number,
                title: title,
                url: url,
                isDraft: isDraft,
                reviewStatus: reviewStatus,
                commentCount: comments.totalCount,
                passedCheckCount: statusCheckRollup?.contexts.nodes.count(where: \.passedCheck) ?? 0,
                actionStatus: GitHubActionSummary.status(for: actionChecks),
                actionRuns: actionRuns
            )
        }

        private var reviewStatus: GitHubPullRequest.ReviewStatus {
            switch reviewDecision {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changesRequested
            default: .awaitingReview
            }
        }

        private var actionChecks: [GitHubActionSummary.Check] {
            statusCheckRollup?.contexts.nodes.compactMap(\.actionCheck) ?? []
        }

        private var actionRuns: [GitHubActionRun] {
            let grouped = Dictionary(grouping: statusCheckRollup?.contexts.nodes ?? [], by: \CheckNode.workflowRun?.id)
            return grouped.compactMap { id, nodes in
                guard
                    let id,
                    let workflowRun = nodes.compactMap(\.workflowRun).first
                else { return nil }
                let status = GitHubActionSummary.status(for: nodes.compactMap(\.actionCheck))
                guard status != .none else { return nil }
                return .init(
                    id: id,
                    repository: repository.nameWithOwner,
                    name: workflowRun.workflow.name ?? workflowRun.displayTitle,
                    pullRequestNumber: number,
                    updatedAt: workflowRun.updatedAt,
                    status: status
                )
            }
        }
    }

    struct Repository: Decodable { let nameWithOwner: String }
    struct Comments: Decodable { let totalCount: Int }
    struct Rollup: Decodable { let contexts: Contexts }
    struct Contexts: Decodable { let nodes: [CheckNode] }

    struct CheckNode: Decodable {
        let typename: String
        let id: String?
        let name: String?
        let status: String?
        let conclusion: String?
        let completedAt: Date?
        let checkSuite: CheckSuite?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename", id, name, status, conclusion, completedAt, checkSuite, state
        }

        var actionCheck: GitHubActionSummary.Check? {
            guard typename == "CheckRun", checkSuite?.app.slug == "github-actions", let status else { return nil }
            return .init(status: status, conclusion: conclusion, completedAt: completedAt)
        }

        var passedCheck: Bool {
            conclusion == "SUCCESS" || state == "SUCCESS"
        }

        var workflowRun: WorkflowRun? {
            guard typename == "CheckRun", checkSuite?.app.slug == "github-actions" else { return nil }
            return checkSuite?.workflowRun
        }
    }

    struct CheckSuite: Decodable {
        let app: App
        let workflowRun: WorkflowRun?
    }
    struct WorkflowRun: Decodable {
        let id: String
        let displayTitle: String
        let updatedAt: Date
        let workflow: Workflow
    }
    struct Workflow: Decodable { let name: String? }
    struct App: Decodable { let slug: String }
}

struct GitHubCLIWorkflowRun: Decodable {
    let databaseId: Int
    let workflowName: String?
    let displayTitle: String
    let event: String
    let headBranch: String?
    let status: String
    let conclusion: String?
    let updatedAt: Date
    let url: URL

    func actionRun(repository: GitHubRepository) -> GitHubActionRun {
        GitHubActionRun(
            id: "\(repository.id)-\(databaseId)",
            repository: repository.nameWithOwner,
            name: workflowName ?? displayTitle,
            event: event,
            ref: headBranch,
            url: url,
            updatedAt: updatedAt,
            status: GitHubActionSummary.status(for: [
                .init(
                    status: status,
                    conclusion: conclusion,
                    completedAt: status.uppercased() == "COMPLETED" ? updatedAt : nil
                )
            ])
        )
    }
}

enum GitHubCLIExecutable {
    static func locate(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var paths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            fileManager.homeDirectoryForCurrentUser.appending(path: ".local/bin/gh").path
        ]
        paths.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appending(path: "gh").path })
        return paths.first(where: fileManager.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}

private extension JSONDecoder {
    static let github: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
