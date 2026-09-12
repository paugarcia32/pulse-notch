import Foundation
import Testing
@testable import PulseNotchCore

struct GitHubPullRequestTests {
    @Test
    func reportsRunningActionsBeforeEarlierFailures() {
        let status = GitHubActionSummary.status(for: [
            .init(status: "COMPLETED", conclusion: "FAILURE"),
            .init(status: "IN_PROGRESS")
        ])

        #expect(status == .running)
    }

    @Test
    func reportsLatestCompletionForSuccessfulActions() {
        let first = Date(timeIntervalSince1970: 1_000)
        let last = Date(timeIntervalSince1970: 2_000)

        let status = GitHubActionSummary.status(for: [
            .init(status: "COMPLETED", conclusion: "SUCCESS", completedAt: first),
            .init(status: "COMPLETED", conclusion: "SUCCESS", completedAt: last)
        ])

        #expect(status == .succeeded(completedAt: last))
    }
}
