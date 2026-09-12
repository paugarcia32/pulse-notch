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
            at: now,
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.map(\.id) == ["calendar-event", "codex", "claude", "cursor", "antigravity"])
    }
}
