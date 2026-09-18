import Testing
@testable import PulseNotchApp

struct DynamicPageVisibilityTests {
    @Test
    func normalModeKeepsEveryConfiguredPage() {
        let activity = DynamicPageActivity(calendar: false, agents: false, github: false, media: false)

        #expect(activity.visiblePages(from: [.github, .calendar, .media], isEnabled: false) == [.github, .calendar, .media])
    }

    @Test
    func dynamicModeKeepsOnlyActivePagesInConfiguredOrder() {
        let activity = DynamicPageActivity(calendar: true, agents: false, github: true, media: false)

        #expect(activity.visiblePages(from: [.github, .agents, .calendar, .media], isEnabled: true) == [.github, .calendar])
    }

    @Test
    func dynamicModeAlwaysKeepsSummaryWhenConfigured() {
        let activity = DynamicPageActivity(calendar: false, agents: false, github: false, media: false)

        #expect(activity.visiblePages(from: [.summary, .calendar], isEnabled: true) == [.summary])
    }
}
