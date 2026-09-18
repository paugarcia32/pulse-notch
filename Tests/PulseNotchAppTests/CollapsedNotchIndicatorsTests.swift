import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

struct CollapsedNotchIndicatorsTests {
    @Test
    func createsAllRelevantIndicatorsBeforeLayoutAppliesItsLimit() {
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

        #expect(indicators.map(\.id) == ["calendar-event", "codex", "claude", "cursor", "antigravity", "opencode"])
        #expect(indicators.first?.content == .upcomingCalendarEvent(minutesUntilStart: 1))
    }

    @Test
    func ordersIndicatorsUsingTheUsersCategoryPriorities() {
        let indicators = [
            CollapsedIndicatorPreview.codex.indicator(instance: 0),
            CollapsedIndicatorPreview.calendar.indicator(instance: 0),
            CollapsedIndicatorPreview.download.indicator(instance: 0)
        ]

        let prioritized = CollapsedNotchIndicators.prioritize(
            indicators,
            using: [.downloads, .codingAgents, .calendar, .githubActions, .mediaPlayback]
        )

        #expect(prioritized.map(\.category) == [.downloads, .codingAgents, .calendar])
    }

    @Test
    func pairedIndicatorsOccupyTheSameLevelOnBothSides() {
        let calendar = CollapsedIndicatorPreview.calendar.indicator(instance: 0)
        let agent = CollapsedIndicatorPreview.codex.indicator(instance: 0)
        let layout = CollapsedNotchLayout(indicators: [calendar, agent], maximumPerSide: 2)

        #expect(layout.levels.count == 2)
        #expect(layout.levels[0].left?.id == calendar.id)
        #expect(layout.levels[0].right?.id == calendar.id)
        #expect(layout.levels[1].left?.id == agent.id)
        #expect(layout.levels[1].right == nil)
    }

    @Test
    func balancesSingleIndicatorsAcrossBothSidesByPriorityLevel() {
        let indicators = [
            CollapsedIndicatorPreview.codex.indicator(instance: 0),
            CollapsedIndicatorPreview.claude.indicator(instance: 0),
            CollapsedIndicatorPreview.cursor.indicator(instance: 0)
        ]
        let layout = CollapsedNotchLayout(indicators: indicators, maximumPerSide: 2)

        #expect(layout.levels.map { $0.left?.id } == ["codex-0", "cursor-0"])
        #expect(layout.levels.map { $0.right?.id } == ["claude-0", nil])
    }

    @Test
    func dropsLowerPriorityLevelsWhenTheNotchIsFull() {
        let indicators = [
            CollapsedIndicatorPreview.calendar.indicator(instance: 0),
            CollapsedIndicatorPreview.codex.indicator(instance: 0),
            CollapsedIndicatorPreview.claude.indicator(instance: 0)
        ]
        let layout = CollapsedNotchLayout(indicators: indicators, maximumPerSide: 1)

        #expect(layout.levels.count == 1)
        #expect(layout.levels[0].left?.category == .calendar)
        #expect(layout.levels[0].right?.category == .calendar)
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
    func showsOneAnimatedIndicatorForEachActiveDownload() {
        let indicators = CollapsedNotchIndicators.make(
            schedule: nil,
            sessions: [],
            actionSessions: [],
            downloads: [
                DetectedDownload(id: "first", byteCount: 100),
                DetectedDownload(id: "second", byteCount: 200)
            ],
            at: Date(timeIntervalSince1970: 1_000),
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.map(\.id) == ["download-first", "download-second"])
        #expect(indicators.allSatisfy { $0.content == .runningDownload })
    }

    @Test
    func prioritizesMediaPlaybackAndIncludesItsCompactIndicator() {
        let playback = MediaPlaybackStatus(
            id: "track",
            title: "Track",
            artist: "Artist",
            duration: 180,
            elapsedTime: 20,
            isPlaying: true
        )

        let indicators = CollapsedNotchIndicators.make(
            schedule: nil,
            sessions: [],
            actionSessions: [],
            mediaPlayback: playback,
            at: Date(timeIntervalSince1970: 1_000),
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.first?.content == .mediaPlayback(playback))
        #expect(indicators.first?.category == .mediaPlayback)
    }

    @Test
    func placesMediaBeforeTheUpcomingCalendarIndicator() {
        let now = Date(timeIntervalSince1970: 1_000)
        let indicators = CollapsedNotchIndicators.make(
            schedule: CalendarEventSchedule(events: [CalendarEvent(
                id: "event", title: "Planning", startsAt: now.addingTimeInterval(60), endsAt: now.addingTimeInterval(3_600)
            )]),
            sessions: [],
            actionSessions: [],
            mediaPlayback: .init(id: "track", title: "Track", artist: "Artist", duration: 180, elapsedTime: 20, isPlaying: true),
            at: now,
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.map(\.id).prefix(2) == ["media-track", "calendar-event"])
    }

    @Test
    func hidesPausedMediaPlaybackFromTheClosedNotch() {
        let indicators = CollapsedNotchIndicators.make(
            schedule: nil,
            sessions: [],
            actionSessions: [],
            mediaPlayback: .init(id: "track", title: "Track", artist: "Artist", duration: 180, elapsedTime: 20, isPlaying: false),
            at: Date(timeIntervalSince1970: 1_000),
            calendarReminderLeadTime: 10 * 60
        )

        #expect(indicators.isEmpty)
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
