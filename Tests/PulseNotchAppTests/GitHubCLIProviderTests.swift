import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

struct GitHubCLIProviderTests {
    @Test
    func decodesPushWorkflowRunWithoutAPullRequest() throws {
        let json = """
        {
          "databaseId": 12345,
          "workflowName": "Release",
          "displayTitle": "v0.1.1",
          "event": "push",
          "headBranch": "v0.1.1",
          "status": "in_progress",
          "conclusion": null,
          "updatedAt": "2026-09-20T10:00:00Z",
          "url": "https://github.com/paugarcia32/pulse-notch/actions/runs/12345"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(GitHubCLIWorkflowRun.self, from: Data(json.utf8))
        let repository = try #require(GitHubRepository(nameWithOwner: "paugarcia32/pulse-notch"))

        let run = value.actionRun(repository: repository)

        #expect(run.id == "paugarcia32/pulse-notch-12345")
        #expect(run.repository == "paugarcia32/pulse-notch")
        #expect(run.name == "Release")
        #expect(run.event == "push")
        #expect(run.ref == "v0.1.1")
        #expect(run.pullRequestNumber == nil)
        #expect(run.status == .running)
    }

    @Test
    func completedWorkflowUsesItsUpdatedDate() throws {
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let value = GitHubCLIWorkflowRun(
            databaseId: 99,
            workflowName: "CI",
            displayTitle: "Build",
            event: "push",
            headBranch: "main",
            status: "completed",
            conclusion: "success",
            updatedAt: updatedAt,
            url: try #require(URL(string: "https://github.com/example/project/actions/runs/99"))
        )
        let repository = try #require(GitHubRepository(nameWithOwner: "example/project"))

        #expect(value.actionRun(repository: repository).status == .succeeded(completedAt: updatedAt))
    }
}
