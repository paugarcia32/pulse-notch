import Foundation
import Testing
@testable import PulseNotchCore

struct GitHubActionTrackerTests {
    @Test
    func retainsCompletedActionAfterItWasObservedRunning() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = GitHubActionTracker()
        tracker.update(runs: [run(status: .running, at: now)], at: now)

        let sessions = tracker.update(
            runs: [run(status: .succeeded(completedAt: now.addingTimeInterval(10)), at: now.addingTimeInterval(10))],
            at: now.addingTimeInterval(10)
        )

        #expect(sessions.first?.status == .completed(.succeeded(completedAt: now.addingTimeInterval(10))))
        #expect(tracker.notificationSessions.count == 1)
    }

    @Test
    func doesNotNotifyActionsThatWereAlreadyFinishedAtStartup() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = GitHubActionTracker()

        tracker.update(runs: [run(status: .failed, at: now)], at: now)

        #expect(tracker.sessions.isEmpty)
        #expect(tracker.notificationSessions.isEmpty)
    }

    private func run(
        status: GitHubPullRequest.ActionStatus,
        at date: Date
    ) -> GitHubActionRun {
        .init(
            id: "run-1",
            repository: "example/project",
            name: "CI",
            pullRequestNumber: 42,
            updatedAt: date,
            status: status
        )
    }
}
