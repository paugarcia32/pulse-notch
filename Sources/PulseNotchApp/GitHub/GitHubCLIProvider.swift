import Foundation
import PulseNotchCore

actor GitHubCLIProvider: GitHubPullRequestProviding {
    func pullRequests() throws -> [GitHubPullRequest] {
        let output = try CommandOutput.read(
            executable: "/usr/bin/env",
            arguments: ["gh", "api", "graphql", "-f", "query=\(query)"],
            timeout: 15
        )
        return try JSONDecoder.github.decode(Response.self, from: Data(output.utf8)).data.search.nodes.map(\.pullRequest)
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
                actionRunners: actionRunners
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

        private var actionRunners: [GitHubPullRequest.ActionRunner] {
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

private extension JSONDecoder {
    static let github: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
