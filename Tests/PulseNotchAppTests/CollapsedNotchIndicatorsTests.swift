import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

struct CollapsedNotchIndicatorsTests {
    @Test
    func prioritizesUpcomingCalendarThenLimitsAgentIndicators() {
        let now = Date(timeIntervalSince1970: 1_000)
        let schedule = CalendarEventSchedule(events: [CalendarEvent(
            id: "event",
            title: "Planning",
            startsAt: now.addingTimeInterval(60),
            endsAt: now.addingTimeInterval(1_860)
        )])
        let sessions = CodingAgentKind.allCases.map { kind in
            CodingAgentSession(
                id: kind.rawValue,
                kind: kind,
                title: "Session",
                detectedAt: now,
                status: .running
            )
        }

        let indicators = CollapsedNotchIndicators.make(
            schedule: schedule,
            sessions: sessions,
            actionSessions: [],
            at: now,
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.map(\.id) == ["calendar-event", "codex", "claude", "cursor", "antigravity"])
        #expect(indicators.first?.content == .upcomingCalendarEvent(minutesUntilStart: 1))
    }

    @Test
    func prioritizesRunningGitHubActionsOverFailedActions() {
        let url = URL(string: "https://github.com/acme/app/pull/1")!
        let actionSessions = [
            actionSession(id: "failed", status: .completed(.failed), url: url),
            actionSession(id: "running", status: .running, url: url)
        ]

        let indicators = CollapsedNotchIndicators.make(
            schedule: nil,
            sessions: [],
            actionSessions: actionSessions,
            at: Date(timeIntervalSince1970: 1_000),
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.map(\.id) == ["github-actions-running"])
    }

    @Test
    func roundsCalendarCountdownUpToTheNextMinute() {
        let now = Date(timeIntervalSince1970: 1_000)
        let schedule = CalendarEventSchedule(events: [CalendarEvent(
            id: "event",
            title: "Planning",
            startsAt: now.addingTimeInterval(119),
            endsAt: now.addingTimeInterval(1_860)
        )])

        let indicators = CollapsedNotchIndicators.make(
            schedule: schedule,
            sessions: [],
            actionSessions: [],
            at: now,
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.first?.content == .upcomingCalendarEvent(minutesUntilStart: 2))
        #expect(indicators.first?.accessibilityLabel == "Next calendar event starts in 2 minutes")
    }

    private func actionSession(
        id: String,
        status: GitHubActionSession.Status,
        url: URL
    ) -> GitHubActionSession {
        GitHubActionSession(
            runner: .init(
            id: id,
                name: "Workflow",
                pullRequestNumber: 1,
                updatedAt: Date(timeIntervalSince1970: 1_000),
                status: status == .running ? .running : .failed
            ),
            detectedAt: Date(timeIntervalSince1970: 1_000),
            status: status
        )
    }
}
