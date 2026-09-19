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
    func eventAfterTodayFallsThroughToNextPriority() throws {
        let tomorrow = try #require(Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: now))
        let event = CalendarEvent(
            id: "tomorrow-event",
            title: "Tomorrow's review",
            startsAt: tomorrow,
            endsAt: tomorrow.addingTimeInterval(1_800)
        )
        let agent = CodingAgentSession(
            id: "agent",
            kind: .codex,
            title: "Implement summary",
            detectedAt: now,
            status: .running
        )

        #expect(SummaryHighlight.select(
            schedule: CalendarEventSchedule(events: [event]),
            pullRequests: [],
            agents: [agent],
            actions: [],
            media: nil,
            priorities: [.calendarEvent, .activeWork],
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
    func activeClockCanAppearInSummary() {
        let clock = ClockStatus(mode: .timer, time: 90, isRunning: true)

        #expect(SummaryHighlight.select(
            schedule: nil,
            pullRequests: [],
            agents: [],
            actions: [],
            media: nil,
            clock: clock,
            priorities: [.clock],
            at: now
        ) == .clock(clock))
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

    @Test
    func mostDepletedUsageLimitAppearsWhenTwentyPercentOrLessRemains() {
        let fiveHour = CodingAgentUsage.Window(
            durationMinutes: 300,
            usedPercent: 80,
            resetsAt: now.addingTimeInterval(3_600)
        )
        let weekly = CodingAgentUsage.Window(
            durationMinutes: 10_080,
            usedPercent: 92,
            resetsAt: now.addingTimeInterval(86_400)
        )

        #expect(SummaryHighlight.select(
            schedule: nil,
            pullRequests: [],
            agents: [],
            actions: [],
            media: nil,
            usage: [
                .available(CodingAgentUsage(kind: .codex, windows: [fiveHour])),
                .available(CodingAgentUsage(kind: .claude, windows: [weekly]))
            ],
            priorities: [.usageLimits],
            at: now
        ) == .usage(kind: .claude, window: weekly))
    }

    @Test
    func healthyUsageLimitDoesNotReplaceAllClear() {
        let window = CodingAgentUsage.Window(
            durationMinutes: 300,
            usedPercent: 79,
            resetsAt: nil
        )

        #expect(SummaryHighlight.select(
            schedule: nil,
            pullRequests: [],
            agents: [],
            actions: [],
            media: nil,
            usage: [.available(CodingAgentUsage(kind: .codex, windows: [window]))],
            priorities: [.usageLimits],
            at: now
        ) == .allClear)
    }
}
