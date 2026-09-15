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
    func batteryModelReportsProviderFailure() async {
        let model = BatteryFeatureModel(provider: BatteryProviderFake(fails: true))

        await model.refresh()

        #expect(model.state == .unavailable)
    }

    @Test
    func batteryModelShowsAnActivityWhenPowerIsConnected() async {
        let provider = BatterySequenceProvider(statuses: [
            BatteryStatus(chargeLevel: 58, isCharging: false, isConnectedToPower: false),
            BatteryStatus(chargeLevel: 58, isCharging: true, isConnectedToPower: true)
        ])
        let model = BatteryFeatureModel(provider: provider)

        await model.refresh()
        #expect(model.chargingActivity == nil)

        await model.refresh()
        #expect(model.chargingActivity?.chargeLevel == 58)
    }

    @Test
    func volumeModelShowsAnActivityWhenVolumeChanges() async {
        let provider = VolumeSequenceProvider(statuses: [
            SystemVolumeStatus(level: 40, isMuted: false),
            SystemVolumeStatus(level: 52, isMuted: false)
        ])
        let model = VolumeFeatureModel(provider: provider)

        await model.refresh()
        #expect(model.activity == nil)

        await model.refresh()
        #expect(model.activity == SystemVolumeStatus(level: 52, isMuted: false))
    }

    @Test
    func brightnessModelShowsAnActivityWhenBrightnessChanges() async {
        let provider = BrightnessSequenceProvider(statuses: [
            DisplayBrightnessStatus(level: 40),
            DisplayBrightnessStatus(level: 52)
        ])
        let model = BrightnessFeatureModel(provider: provider)

        await model.refresh()
        #expect(model.activity == nil)

        await model.refresh()
        #expect(model.activity == DisplayBrightnessStatus(level: 52))
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
        preferences.setTransientSystemActivityDurationSeconds(6)
        preferences.setShowChargingActivity(false)
        preferences.setShowVolumeActivity(false)
        preferences.setShowBrightnessActivity(false)
        preferences.setPreferredDisplayID("42")
        preferences.setExternalNotchStyle(.rectangle)
        preferences.setCollapsedIndicatorMaximumPerSide(4)
        preferences.setCollapsedIndicatorCategory(.githubActions, isVisible: false)
        preferences.setTestingFeaturesEnabled(true)
        preferences.triggerTestingSystemActivity(.volume)

        let restoredPreferences = NotchPreferences(defaults: defaults)
        #expect(restoredPreferences.pageOrder == [.github, .calendar, .agents])
        #expect(restoredPreferences.orderedVisiblePages == [.github, .calendar])
        #expect(restoredPreferences.page(for: .firstPage) == .github)
        #expect(restoredPreferences.shortcut(for: .firstPage).displayName == "⌥⌘G")
        #expect(restoredPreferences.calendarReminderLeadTimeMinutes == 5)
        #expect(restoredPreferences.calendarReminderLeadTime == 5 * 60)
        #expect(restoredPreferences.transientSystemActivityDurationSeconds == 6)
        #expect(!restoredPreferences.showChargingActivity)
        #expect(!restoredPreferences.showVolumeActivity)
        #expect(!restoredPreferences.showBrightnessActivity)
        #expect(restoredPreferences.preferredDisplayID == "42")
        #expect(restoredPreferences.externalNotchStyle == .rectangle)
        #expect(restoredPreferences.collapsedIndicatorMaximumPerSide == 4)
        #expect(!restoredPreferences.isCollapsedIndicatorCategoryVisible(.githubActions))
        #expect(restoredPreferences.isCollapsedIndicatorCategoryVisible(.calendar))
        #expect(restoredPreferences.isCollapsedIndicatorCategoryVisible(.codingAgents))
        #expect(restoredPreferences.testingFeaturesEnabled)
        #expect(preferences.testingSystemActivity == .volume)
        #expect(preferences.testingSystemActivityTrigger != nil)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func closedNotchIndicatorPreviewsCanBeEnabledAndDisabled() {
        let preferences = NotchPreferences(defaults: UserDefaults(suiteName: "PulseNotchTests.\(#function)")!)

        preferences.setTestingFeaturesEnabled(true)
        preferences.setCollapsedIndicatorPreviewCount(2, for: .calendar)
        preferences.setCollapsedIndicatorPreviewCount(3, for: .githubActions)
        preferences.setCollapsedIndicatorMaximumPerSide(9)
        preferences.setCollapsedIndicatorPreviewCount(9, for: .codex)

        #expect(preferences.collapsedIndicatorPreviewCount(.calendar) == 1)
        #expect(preferences.collapsedIndicatorPreviewCount(.githubActions) == 3)
        #expect(preferences.collapsedIndicatorPreviewCount(.codex) == 5)
        #expect(preferences.collapsedIndicatorMaximumPerSide == 5)

        preferences.setTestingFeaturesEnabled(false)

        #expect(preferences.collapsedIndicatorPreviewCounts.isEmpty)
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

private struct BatteryProviderFake: BatteryStatusProviding {
    let fails: Bool

    func currentBatteryStatus() async throws -> BatteryStatus {
        if fails { throw BatteryStatusProviderError.unavailable }
        return BatteryStatus(chargeLevel: 50, isCharging: false, isConnectedToPower: false)
    }
}

private actor BatterySequenceProvider: BatteryStatusProviding {
    private var statuses: [BatteryStatus]

    init(statuses: [BatteryStatus]) {
        self.statuses = statuses
    }

    func currentBatteryStatus() async throws -> BatteryStatus {
        statuses.removeFirst()
    }
}

private actor VolumeSequenceProvider: SystemVolumeProviding {
    private var statuses: [SystemVolumeStatus]

    init(statuses: [SystemVolumeStatus]) {
        self.statuses = statuses
    }

    func currentVolumeStatus() async throws -> SystemVolumeStatus {
        statuses.removeFirst()
    }
}

private actor BrightnessSequenceProvider: DisplayBrightnessProviding {
    private var statuses: [DisplayBrightnessStatus]

    init(statuses: [DisplayBrightnessStatus]) {
        self.statuses = statuses
    }

    func currentDisplayBrightness() async throws -> DisplayBrightnessStatus {
        statuses.removeFirst()
    }
}
