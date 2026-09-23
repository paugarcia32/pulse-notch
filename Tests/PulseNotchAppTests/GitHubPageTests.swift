import Testing
@testable import PulseNotchApp

@MainActor
struct GitHubPageTests {
    @Test
    func runningActionsDoNotClaimEverythingIsCaughtUpWithoutPullRequests() {
        #expect(GitHubPage.activityDescription(pullRequests: 0, running: 1) == "1 running")
        #expect(GitHubPage.activityDescription(pullRequests: 2, running: 1) == "2 open · 1 running")
        #expect(GitHubPage.activityDescription(pullRequests: 0, running: 0) == "All caught up")
    }
}
