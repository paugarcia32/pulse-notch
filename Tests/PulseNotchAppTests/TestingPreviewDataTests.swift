import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

@MainActor
struct TestingPreviewDataTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func pullRequestPreviewsFeedSummaryAndActivateGitHubWithoutRunningActions() throws {
        let suite = "PulseNotchTests.\(#function)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchPreferences(defaults: defaults)
        preferences.setTestingFeaturesEnabled(true)
        preferences.setSummaryPreviewCount(1, for: .githubAttention)
        preferences.setSummaryPreviewCount(1, for: .openPullRequest)

        let preview = NotchSurface.TestingPreviewData.make(preferences: preferences, at: now)
        let pullRequests = try #require(preview.pullRequests)

        #expect(pullRequests.map(\.number) == [42, 43])
        #expect(preview.actions == nil)
        #expect(preview.hasGitHubActivity)
        #expect(SummaryHighlight.select(
            schedule: preview.schedule,
            pullRequests: pullRequests,
            agents: [],
            actions: [],
            media: nil,
            priorities: [.githubAttention, .openPullRequest],
            at: now
        ) == .pullRequest(pullRequests[0]))
        let pages = DynamicPageActivity(
            calendar: preview.schedule != nil,
            agents: false,
            github: preview.hasGitHubActivity,
            media: false
        ).visiblePages(from: [.summary, .github], isEnabled: true)
        #expect(pages == [.summary, .github])
    }

    @Test
    func calendarCountdownPreviewRemainsVisibleAcrossDayBoundary() throws {
        let suite = "PulseNotchTests.\(#function)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchPreferences(defaults: defaults)
        preferences.setTestingFeaturesEnabled(true)
        preferences.setCollapsedIndicatorPreviewCount(1, for: .calendar)

        let day = try #require(Calendar.autoupdatingCurrent.dateInterval(of: .day, for: now))
        let nearMidnight = day.end.addingTimeInterval(-30)
        let preview = NotchSurface.TestingPreviewData.make(preferences: preferences, at: nearMidnight)
        let event = try #require(preview.schedule?.events.first)
        let indicator = CollapsedIndicatorPreview.calendar.indicator(instance: 0, at: nearMidnight)

        #expect(event.startsAt > nearMidnight && event.startsAt < day.end)
        #expect(preview.schedule?.events(on: nearMidnight) == [event])
        #expect(indicator.content == .upcomingCalendarEvent(minutesUntilStart: 1))
        #expect(SummaryHighlight.select(
            schedule: preview.schedule,
            pullRequests: [],
            agents: [],
            actions: [],
            media: nil,
            priorities: [.calendarEvent],
            at: nearMidnight
        ) == .event(event))
    }
}
