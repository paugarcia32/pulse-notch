import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

struct SummaryPageTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func nextEventTakesPriorityOverOtherSummaryContent() {
        let event = CalendarEvent(
            id: "event",
            title: "Design review",
            startsAt: now.addingTimeInterval(600),
            endsAt: now.addingTimeInterval(2_400)
        )
        let media = MediaPlaybackStatus(
            id: "track",
            title: "Song",
            artist: "Artist",
            duration: 180,
            elapsedTime: 20,
            isPlaying: true
        )

        #expect(SummaryHighlight.select(
            schedule: CalendarEventSchedule(events: [event]),
            pullRequests: [],
            agents: [],
            actions: [],
            media: media,
            priorities: SummaryPriority.allCases,
            at: now
        ) == .event(event))
    }

    @Test
    func activeWorkReplacesMissingEvent() {
        let agent = CodingAgentSession(
            id: "agent",
            kind: .codex,
            title: "Implement summary",
            detectedAt: now,
            status: .running
        )

        #expect(SummaryHighlight.select(
            schedule: CalendarEventSchedule(events: []),
            pullRequests: [],
            agents: [agent],
            actions: [],
            media: nil,
            priorities: SummaryPriority.allCases,
            at: now
        ) == .activeWork(agentCount: 1, actionCount: 0))
    }

    @Test
    func summaryIsAllClearWhenNothingIsRelevant() {
        #expect(SummaryHighlight.select(
            schedule: nil,
            pullRequests: [],
            agents: [],
            actions: [],
            media: nil,
            priorities: SummaryPriority.allCases,
            at: now
        ) == .allClear)
    }

    @Test
    func configuredPriorityOrderChoosesActiveWorkBeforeCalendar() {
        let event = CalendarEvent(
            id: "event",
            title: "Design review",
            startsAt: now.addingTimeInterval(600),
            endsAt: now.addingTimeInterval(2_400)
        )
        let agent = CodingAgentSession(
            id: "agent",
            kind: .codex,
            title: "Implement priorities",
            detectedAt: now,
            status: .running
        )

        #expect(SummaryHighlight.select(
            schedule: CalendarEventSchedule(events: [event]),
            pullRequests: [],
            agents: [agent],
            actions: [],
            media: nil,
            priorities: [.activeWork, .calendarEvent],
            at: now
        ) == .activeWork(agentCount: 1, actionCount: 0))
    }
}
