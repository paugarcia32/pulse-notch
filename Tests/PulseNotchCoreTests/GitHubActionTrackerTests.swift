import Foundation
import Testing
@testable import PulseNotchCore

struct GitHubActionTrackerTests {
    @Test
    func retainsCompletedActionAfterItWasObservedRunning() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = GitHubActionTracker()
        tracker.update(runners: [runner(status: .running, at: now)], at: now)

        let sessions = tracker.update(
            runners: [runner(status: .succeeded(completedAt: now.addingTimeInterval(10)), at: now.addingTimeInterval(10))],
            at: now.addingTimeInterval(10)
        )

        #expect(sessions.first?.status == .completed(.succeeded(completedAt: now.addingTimeInterval(10))))
        #expect(tracker.notificationSessions.count == 1)
    }

    @Test
    func doesNotNotifyActionsThatWereAlreadyFinishedAtStartup() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = GitHubActionTracker()

        tracker.update(runners: [runner(status: .failed, at: now)], at: now)

        #expect(tracker.sessions.isEmpty)
        #expect(tracker.notificationSessions.isEmpty)
    }

    private func runner(
        status: GitHubPullRequest.ActionStatus,
        at date: Date
    ) -> GitHubPullRequest.ActionRunner {
        .init(id: "run-1", name: "CI", pullRequestNumber: 42, updatedAt: date, status: status)
    }
}
