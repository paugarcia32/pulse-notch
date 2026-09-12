import Foundation
import Testing
@testable import PulseNotchCore

struct CodingAgentTrackerTests {
    @Test
    func usageWindowReportsClampedRemainingCapacity() {
        let ordinary = CodingAgentUsage.Window(
            durationMinutes: 300,
            usedPercent: 29,
            resetsAt: nil
        )
        let exhausted = CodingAgentUsage.Window(
            durationMinutes: 10_080,
            usedPercent: 120,
            resetsAt: nil
        )

        #expect(ordinary.remainingPercent == 71)
        #expect(exhausted.remainingPercent == 0)
    }

    @Test
    func newlyDetectedAgentIsRunning() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = CodingAgentTracker()

        let sessions = tracker.update(
            active: [DetectedCodingAgent(
                id: "codex-12",
                kind: .codex,
                title: "Fix the build"
            )],
            at: now
        )

        #expect(
            sessions == [
                CodingAgentSession(
                    id: "codex-12",
                    kind: .codex,
                    title: "Fix the build",
                    detectedAt: now,
                    status: .running
                )
            ]
        )
    }

    @Test
    func sessionRetainsWorkspaceAndStartTime() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = CodingAgentTracker()

        let session = tracker.update(
            active: [DetectedCodingAgent(
                id: "codex-12",
                kind: .codex,
                title: "Fix the build",
                workingDirectory: "/tmp/project",
                gitBranch: "feature/notch",
                startedAt: now.addingTimeInterval(-60)
            )],
            at: now
        ).first

        #expect(session?.workingDirectory == "/tmp/project")
        #expect(session?.gitBranch == "feature/notch")
        #expect(session?.startedAt == now.addingTimeInterval(-60))
    }

    @Test
    func disappearingAgentRemainsAsRecentlyCompleted() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = CodingAgentTracker()
        tracker.update(
            active: [DetectedCodingAgent(
                id: "claude-21",
                kind: .claude,
                title: "Review changes"
            )],
            at: now
        )

        let sessions = tracker.update(
            active: [],
            at: now.addingTimeInterval(10)
        )

        #expect(
            sessions.first?.status == .completed(
                at: now.addingTimeInterval(10)
            )
        )
    }

    @Test
    func completedAgentExpiresAfterRetentionWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = CodingAgentTracker(completedRetention: 30)
        tracker.update(
            active: [DetectedCodingAgent(
                id: "cursor-4",
                kind: .cursor,
                title: "Add tests"
            )],
            at: now
        )
        tracker.update(active: [], at: now.addingTimeInterval(10))

        let sessions = tracker.update(
            active: [],
            at: now.addingTimeInterval(40)
        )

        #expect(sessions.isEmpty)
    }

    @Test
    func completedNotificationIsConsumedWhenAcknowledged() {
        let now = Date(timeIntervalSince1970: 1_000)
        let agent = DetectedCodingAgent(
            id: "codex-7",
            kind: .codex,
            title: "Finish feature"
        )
        var tracker = CodingAgentTracker()
        tracker.update(active: [agent], at: now)
        tracker.update(active: [], at: now.addingTimeInterval(10))

        #expect(tracker.notificationSessions.count == 1)

        tracker.acknowledgeCompletedSessions()

        #expect(tracker.notificationSessions.isEmpty)
        #expect(tracker.sessions.count == 1)

        tracker.update(active: [agent], at: now.addingTimeInterval(20))
        tracker.update(active: [], at: now.addingTimeInterval(30))

        #expect(tracker.notificationSessions.count == 1)
    }
}
