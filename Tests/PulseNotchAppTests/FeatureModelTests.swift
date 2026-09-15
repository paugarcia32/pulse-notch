import Foundation
import PulseNotchCore
import Testing
@testable import PulseNotchApp

@MainActor
struct FeatureModelTests {
    @Test
    func calendarModelReportsDeniedAccess() async {
        let model = CalendarFeatureModel(provider: CalendarProviderFake(deniesAccess: true))

        await model.refresh(at: Date(timeIntervalSince1970: 1_000))

        #expect(model.state == .accessDenied)
    }

    @Test
    func codingAgentModelReportsDetectionFailure() async {
        let model = CodingAgentFeatureModel(
            provider: CodingAgentProviderFake(failsDetection: true)
        )

        await model.refresh(at: Date(timeIntervalSince1970: 1_000))

        #expect(model.state == .unavailable)
    }

    @Test
    func codingAgentModelRetainsPerAgentUsageAvailability() async {
        let model = CodingAgentFeatureModel(
            provider: CodingAgentProviderFake(
                usage: [.unavailable(.claude)]
            )
        )

        await model.refreshUsage()

        #expect(model.usageState == .loaded([.unavailable(.claude)]))
    }

    @Test
    func githubModelReportsProviderFailure() async {
        let model = GitHubFeatureModel(provider: GitHubProviderFake(fails: true))

        await model.refresh()

        #expect(model.state == .unavailable)
    }

    @Test
    func moreEventsLabelIncludesTheRemainingEventCount() {
        #expect(CalendarPage.moreEventsTitle(remainingCount: 3) == "Show 3 more events")
    }

    @Test
    func commandOutputTerminatesCommandsThatExceedTheirDeadline() {
        #expect(throws: CodingAgentProviderError.commandTimedOut) {
            _ = try CommandOutput.read(
                executable: "/bin/sleep",
                arguments: ["1"],
                timeout: 0
            )
        }
    }

    @Test
    func pagePreferencesPersistOrderAndVisibility() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)

        preferences.setVisible(.agents, isVisible: false)
        preferences.movePages(from: IndexSet(integer: 2), to: 0)
        preferences.setShortcut(AppShortcut(key: "g", modifiers: [.command, .option]), for: .firstPage)
        preferences.setCalendarReminderLeadTimeMinutes(5)
        preferences.setPreferredDisplayID("42")
        preferences.setExternalNotchStyle(.rectangle)
        preferences.setCollapsedIndicatorMaximumPerSide(4)
        preferences.setTestingFeaturesEnabled(true)

        let restoredPreferences = NotchPreferences(defaults: defaults)
        #expect(restoredPreferences.pageOrder == [.github, .calendar, .agents])
        #expect(restoredPreferences.orderedVisiblePages == [.github, .calendar])
        #expect(restoredPreferences.page(for: .firstPage) == .github)
        #expect(restoredPreferences.shortcut(for: .firstPage).displayName == "⌥⌘G")
        #expect(restoredPreferences.calendarReminderLeadTimeMinutes == 5)
        #expect(restoredPreferences.calendarReminderLeadTime == 5 * 60)
        #expect(restoredPreferences.preferredDisplayID == "42")
        #expect(restoredPreferences.externalNotchStyle == .rectangle)
        #expect(restoredPreferences.collapsedIndicatorMaximumPerSide == 4)
        #expect(restoredPreferences.testingFeaturesEnabled)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func closedNotchIndicatorPreviewsCanBeEnabledAndDisabled() {
        let preferences = NotchPreferences(defaults: UserDefaults(suiteName: "PulseNotchTests.\(#function)")!)

        preferences.setTestingFeaturesEnabled(true)
        preferences.setCollapsedIndicatorPreview(.calendar, isEnabled: true)
        preferences.setCollapsedIndicatorPreview(.githubActions, isEnabled: true)
        preferences.setCollapsedIndicatorPreview(.calendar, isEnabled: false)
        preferences.setCollapsedIndicatorMaximumPerSide(9)

        #expect(preferences.collapsedIndicatorPreviews == [.githubActions])
        #expect(preferences.collapsedIndicatorMaximumPerSide == 5)

        preferences.setTestingFeaturesEnabled(false)

        #expect(preferences.collapsedIndicatorPreviews.isEmpty)
    }
}

private struct CalendarProviderFake: CalendarEventProviding {
    let deniesAccess: Bool

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        if deniesAccess {
            throw CalendarEventProviderError.accessDenied
        }
        return []
    }
}

private struct CodingAgentProviderFake: CodingAgentProviding {
    let failsDetection: Bool
    let usage: [CodingAgentUsageAvailability]

    init(
        failsDetection: Bool = false,
        usage: [CodingAgentUsageAvailability] = []
    ) {
        self.failsDetection = failsDetection
        self.usage = usage
    }

    func activeAgents() async throws -> [DetectedCodingAgent] {
        if failsDetection {
            throw CodingAgentProviderError.commandFailed
        }
        return []
    }

    func usage() async throws -> [CodingAgentUsageAvailability] {
        usage
    }
}

private struct GitHubProviderFake: GitHubPullRequestProviding {
    let fails: Bool

    func pullRequests() async throws -> [GitHubPullRequest] {
        if fails { throw CocoaError(.fileReadUnknown) }
        return []
    }
}
