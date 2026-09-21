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
    func runningAgentsDoNotReplaceMissingSummaryContent() {
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
        ) == .allClear)
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
            priorities: [.calendarEvent],
            at: now
        ) == .allClear)
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
    func configuredPriorityOrderChoosesCalendarContent() {
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
            priorities: [.calendarEvent],
            at: now
        ) == .event(event))
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

    @Test
    func summaryPreviewsProduceTheirExpectedHighlight() throws {
        let attention = try #require(SummaryPreview.githubAttention.testingPullRequest(at: now))
        #expect(SummaryHighlight.select(
            schedule: nil,
            pullRequests: [attention],
            agents: [],
            actions: [],
            media: nil,
            priorities: [.githubAttention],
            at: now
        ) == .pullRequest(attention))

        let open = try #require(SummaryPreview.openPullRequest.testingPullRequest(at: now))
        #expect(SummaryHighlight.select(
            schedule: nil,
            pullRequests: [open],
            agents: [],
            actions: [],
            media: nil,
            priorities: [.openPullRequest],
            at: now
        ) == .pullRequest(open))

        let usage = try #require(SummaryPreview.usageLimits.testingUsage(at: now))
        guard case let .available(codingUsage) = try #require(usage.first) else {
            Issue.record("Expected an available usage preview")
            return
        }
        let window = try #require(codingUsage.windows.first)
        #expect(SummaryHighlight.select(
            schedule: nil,
            pullRequests: [],
            agents: [],
            actions: [],
            media: nil,
            usage: usage,
            priorities: [.usageLimits],
            at: now
        ) == .usage(kind: .codex, window: window))
    }
}
