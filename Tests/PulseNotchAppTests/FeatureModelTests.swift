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

        #expect(model.state == .unavailable(.requestFailed))
    }

    @Test
    func githubModelTracksRepositoryActionWithoutAPullRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let run = GitHubActionRun(
            id: "repo-1",
            repository: "paugarcia32/pulse-notch",
            name: "Release",
            event: "push",
            ref: "v0.1.1",
            updatedAt: now,
            status: .running
        )
        let model = GitHubFeatureModel(provider: GitHubProviderFake(
            activity: .init(pullRequests: [], actionRuns: [run])
        ))

        await model.refresh(
            repositories: [try #require(GitHubRepository(nameWithOwner: "paugarcia32/pulse-notch"))],
            at: now
        )

        #expect(model.state == .loaded([]))
        #expect(model.actionSessions.first?.run == run)
    }

    @Test
    func githubModelReportsMissingCommandLineTool() async {
        let model = GitHubFeatureModel(provider: GitHubCLIProvider(executableURL: nil))

        await model.refresh()

        #expect(model.state == .unavailable(.commandLineToolMissing))
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
    func brightnessModelShowsAnActivityOnlyForBrightnessKeyPresses() async {
        let provider = BrightnessSequenceProvider(statuses: [
            DisplayBrightnessStatus(level: 40),
            DisplayBrightnessStatus(level: 60)
        ])
        let model = BrightnessFeatureModel(provider: provider)

        #expect(model.activity == nil)

        await model.refreshForBrightnessKeyPress()
        #expect(model.activity == DisplayBrightnessStatus(level: 40))

        model.consumeActivity()
        #expect(model.activity == nil)

        await model.refreshForBrightnessKeyPress()
        #expect(model.activity == DisplayBrightnessStatus(level: 60))
    }

    @Test
    func recognizesBrightnessKeyDownButNotOtherSystemEvents() {
        #expect(BrightnessKeyPress.isBrightnessKeyDown(subtype: 8, data1: (2 << 16) | (0x0A << 8)))
        #expect(BrightnessKeyPress.isBrightnessKeyDown(subtype: 8, data1: (3 << 16) | (0x0A << 8)))
        #expect(!BrightnessKeyPress.isBrightnessKeyDown(subtype: 8, data1: (2 << 16) | (0x0B << 8)))
        #expect(!BrightnessKeyPress.isBrightnessKeyDown(subtype: 8, data1: (0 << 16) | (0x0A << 8)))
        #expect(!BrightnessKeyPress.isBrightnessKeyDown(subtype: 7, data1: (2 << 16) | (0x0A << 8)))
    }

    @Test
    func brightnessDoesNotReplaceChargingActivity() throws {
        let model = SystemActivityFeatureModel()
        model.present(kind: .charging, level: 58)
        let charging = try #require(model.activity)

        model.present(kind: .brightness, level: 75)

        #expect(model.activity == charging)
        model.dismiss(id: charging.id)
        model.present(kind: .brightness, level: 75)
        #expect(model.activity?.kind == .brightness)
    }

    @Test
    func brightnessDoesNotHideVolumeChanges() {
        let model = SystemActivityFeatureModel()
        model.present(kind: .brightness, level: 40)
        model.present(kind: .volume(isMuted: false), level: 50)
        let volume = model.activity

        model.present(kind: .brightness, level: 60)

        #expect(model.activity == volume)
        model.present(kind: .volume(isMuted: false), level: 55)
        #expect(model.activity?.level == 55)
    }

    @Test
    func volumeFallsBackToAvailableOutputChannels() {
        let volume = VolumeChannelReading.volume { channel in
            switch channel {
            case 1: 0.4
            case 2: 0.6
            default: nil
            }
        }

        #expect(volume == 0.5)
        #expect(VolumeChannelReading.volume { $0 == 2 ? 0.7 : nil } == 0.7)
        #expect(VolumeChannelReading.volume { _ in nil } == nil)
        #expect(VolumeChannelReading.volume { $0 == 0 ? 0.8 : 0.2 } == 0.8)
    }

    @Test
    func mediaPlaybackModelShowsTheActiveSystemItem() async {
        let playback = MediaPlaybackStatus(
            id: "track",
            title: "Track",
            artist: "Artist",
            duration: 180,
            elapsedTime: 20,
            isPlaying: true
        )
        let model = MediaPlaybackFeatureModel(provider: MediaPlaybackProviderFake(playback: playback))

        await model.refresh()

        #expect(model.playback == playback)
    }

    @Test
    func pausedMediaPageExpiresAfterFiveMinutes() async {
        let playback = MediaPlaybackStatus(
            id: "track",
            title: "Track",
            artist: "Artist",
            duration: 180,
            elapsedTime: 20,
            isPlaying: false
        )
        let model = MediaPlaybackFeatureModel(provider: MediaPlaybackProviderFake(playback: playback))
        let pausedAt = Date(timeIntervalSinceReferenceDate: 1_000)

        await model.refresh(at: pausedAt)

        #expect(model.isPageActive(at: pausedAt.addingTimeInterval(5 * 60)))
        #expect(!model.isPageActive(at: pausedAt.addingTimeInterval(5 * 60 + 1)))
    }

    @Test
    func mediaPlaybackModelAdvancesTheElapsedTimeBetweenRefreshes() async {
        let playback = MediaPlaybackStatus(
            id: "track",
            title: "Track",
            artist: "Artist",
            duration: 180,
            elapsedTime: 20,
            isPlaying: true
        )
        let model = MediaPlaybackFeatureModel(provider: MediaPlaybackProviderFake(playback: playback))
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000)

        await model.refresh(at: referenceDate)

        #expect(model.elapsedTime(at: referenceDate.addingTimeInterval(3)) == 23)
    }

    @Test
    func mediaPlaybackModelUpdatesPlayPauseBeforeTheNextPoll() async {
        let playback = MediaPlaybackStatus(
            id: "track", title: "Track", artist: "Artist", duration: 180, elapsedTime: 20, isPlaying: true
        )
        let provider = MediaPlaybackCommandProvider(playback: playback)
        let model = MediaPlaybackFeatureModel(provider: provider)

        await model.refresh()
        await model.send(.togglePlayPause)

        #expect(provider.commands == [.togglePlayPause])
        #expect(model.playback?.isPlaying == false)
        #expect(model.isPageActive(at: .now))
    }

    @Test
    func mediaPlaybackReaderDecodesTheSystemNowPlayingPayload() throws {
        let playback = try MediaRemotePlaybackProvider.playback(from: """
        {"uniqueIdentifier":"spotify:track:1","title":"Track","artist":"Artist","duration":180,"elapsedTime":20,"playbackRate":1,"isPlaying":true,"artworkData":"AQID"}
        """)

        #expect(playback == MediaPlaybackStatus(
            id: "spotify:track:1",
            title: "Track",
            artist: "Artist",
            duration: 180,
            elapsedTime: 20,
            isPlaying: true,
            artworkData: Data([1, 2, 3])
        ))
    }

    @Test
    func mediaPlaybackAdapterReaderDecodesArtworkAndPlayingState() throws {
        let playback = try MediaRemoteAdapterPlaybackProvider.playback(from: """
        {"uniqueIdentifier":"spotify:track:1","title":"Track","artist":"Artist","duration":180,"elapsedTime":20,"playing":true,"artworkData":"AQID"}
        """)

        #expect(playback == MediaPlaybackStatus(
            id: "spotify:track:1",
            title: "Track",
            artist: "Artist",
            duration: 180,
            elapsedTime: 20,
            isPlaying: true,
            artworkData: Data([1, 2, 3])
        ))
    }

    @Test
    func bluetoothHeadphonesModelShowsOnlyNewConnections() async {
        let model = BluetoothHeadphonesFeatureModel(provider: BluetoothHeadphonesSequenceProvider(statuses: [
            [BluetoothHeadphonesStatus(id: "existing")],
            [BluetoothHeadphonesStatus(id: "existing"), BluetoothHeadphonesStatus(id: "new", batteryLevel: 72)]
        ]))

        #expect(await model.refresh() == nil)

        #expect(await model.refresh() == BluetoothHeadphonesStatus(id: "new", batteryLevel: 72))
    }

    @Test
    func bluetoothHeadphonesModelUpdatesANewConnectionWhenItsBatteryArrives() async {
        let model = BluetoothHeadphonesFeatureModel(provider: BluetoothHeadphonesSequenceProvider(statuses: [
            [],
            [BluetoothHeadphonesStatus(id: "new")],
            [BluetoothHeadphonesStatus(id: "new", batteryLevel: 72)]
        ]))

        let start = Date(timeIntervalSince1970: 0)
        #expect(await model.refresh(at: start) == nil)
        #expect(await model.refresh(at: start.addingTimeInterval(1)) == nil)

        #expect(await model.refresh(at: start.addingTimeInterval(1.2)) == BluetoothHeadphonesStatus(id: "new", batteryLevel: 72))
    }

    @Test
    func bluetoothHeadphonesModelShowsANeutralBatteryOnlyAfterTheWaitExpires() async {
        let model = BluetoothHeadphonesFeatureModel(provider: BluetoothHeadphonesSequenceProvider(statuses: [
            [],
            [BluetoothHeadphonesStatus(id: "new")],
            [BluetoothHeadphonesStatus(id: "new")]
        ]))
        let start = Date(timeIntervalSince1970: 0)

        #expect(await model.refresh(at: start) == nil)
        #expect(await model.refresh(at: start.addingTimeInterval(1)) == nil)
        #expect(await model.refresh(at: start.addingTimeInterval(1.8)) == BluetoothHeadphonesStatus(id: "new"))
    }

    @Test
    func bluetoothHeadphonesActivityUsesAHeadphonesAndBatteryPresentation() {
        let activity = SystemActivityFeatureModel.Activity(
            kind: .bluetoothHeadphones(batteryLevel: 72),
            level: 72
        )

        #expect(activity.symbolName == "headphones")
        #expect(activity.trailingSymbolName == "battery.75percent")
        #expect(!activity.showsCircularLevel)
    }

    @Test
    func bluetoothBatteryReaderParsesAccessoryPowerSourceLevels() {
        let levels = BluetoothHeadphonesProvider.accessoryBatteryLevels(output: """
        Now drawing from 'Battery Power'
         - AirPods Pro (id=123) 72%; connected: yes
         - WH-1000XM5 48%; connected: yes
        """)

        #expect(levels["airpodspro"] == 72)
        #expect(levels["wh1000xm5"] == 48)
    }

    @Test
    func bluetoothBatteryReaderMatchesSystemProfilerAddressBeforeName() {
        let levels = BluetoothHeadphonesProvider.profilerBatteryLevels(root: [
            "device_connected": [[
                "AirPods": [
                    "device_address": "AA-BB-CC-DD-EE-FF",
                    "device_batteryLevelLeft": "72%",
                    "device_batteryLevelRight": "70%",
                    "device_batteryLevelCase": "48%"
                ]
            ]]
        ])

        #expect(levels.addresses["AABBCCDDEEFF"] == 72)
        #expect(levels.names["airpods"] == 72)
    }

    @Test
    func downloadModelShowsDownloadsThatAppearAfterMonitoringStarts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let provider = DownloadSequenceProvider(snapshots: [
            [DetectedDownload(id: "existing", byteCount: 100)],
            [DetectedDownload(id: "existing", byteCount: 100), DetectedDownload(id: "new", byteCount: 0)]
        ])
        let model = DownloadFeatureModel(provider: provider)
        await model.startMonitoring(directory: directory)
        await model.refresh()

        #expect(model.activeDownloads.map(\.id) == ["new"])
        model.stopMonitoring()
    }

    @Test
    func downloadModelPublishesUpdatedProgress() async {
        let provider = DownloadSequenceProvider(snapshots: [
            [],
            [DetectedDownload(id: "new", byteCount: 25, totalByteCount: 100)],
            [DetectedDownload(id: "new", byteCount: 50, totalByteCount: 100)]
        ])
        let model = DownloadFeatureModel(provider: provider)
        await model.startMonitoring(directory: URL(fileURLWithPath: "/Downloads", isDirectory: true))

        await model.refresh()
        await model.refresh()

        #expect(model.activeDownloads.first?.percentage == 50)
    }

    @Test
    func downloadModelShowsHomebrewActivityAlreadyRunningWhenMonitoringStarts() async {
        let activity = DetectedDownload(
            id: "homebrew-update",
            fileName: "Updating Homebrew",
            byteCount: 0,
            source: .homebrew
        )
        let provider = DownloadSequenceProvider(snapshots: [[activity], [activity]])
        let model = DownloadFeatureModel(provider: provider)

        await model.startMonitoring(
            directory: URL(fileURLWithPath: "/Downloads", isDirectory: true),
            includeHomebrew: true
        )
        await model.refresh()

        #expect(model.activeDownloads == [activity])
    }

    @Test
    func homebrewProcessParserFindsPackageOperationsWithoutDuplicates() {
        let downloads = DownloadsDirectoryProvider.homebrewDownloads(from: """
        100 /opt/homebrew/bin/brew update
        101 /opt/homebrew/Library/Homebrew/vendor/portable-ruby/current/bin/ruby /opt/homebrew/Library/Homebrew/brew.rb update --auto-update
        102 /opt/homebrew/bin/brew upgrade ripgrep
        103 /usr/bin/curl https://example.com/archive.tar.gz
        """)

        #expect(downloads.map(\.id) == ["homebrew-update", "homebrew-upgrade"])
        #expect(downloads.allSatisfy { $0.source == .homebrew && $0.percentage == nil })
    }

    @Test
    func safariDownloadMetadataProvidesNameLocationAndProgress() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadURL = directory.appendingPathComponent("Archive.zip.download", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist: [String: Any] = [
            "DownloadEntryProgressBytesSoFar": 75,
            "DownloadEntryProgressTotalToLoad": 100
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: downloadURL.appendingPathComponent("Info.plist"))

        let download = DownloadsDirectoryProvider.download(at: downloadURL)

        #expect(download.fileName == "Archive.zip")
        #expect(download.directoryURL == directory)
        #expect(download.byteCount == 75)
        #expect(download.totalByteCount == 100)
        #expect(download.percentage == 75)
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
    func permissionGatedFeaturesStartDisabledAndPersistOptIn() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)

        #expect(!preferences.showBluetoothHeadphonesActivity)
        #expect(!preferences.showDownloads)

        preferences.setShowBluetoothHeadphonesActivity(true)
        preferences.setShowDownloads(true)

        let restoredPreferences = NotchPreferences(defaults: defaults)
        #expect(restoredPreferences.showBluetoothHeadphonesActivity)
        #expect(restoredPreferences.showDownloads)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func dynamicPagesStartEnabledAndPersistOptOut() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)

        #expect(preferences.dynamicPagesEnabled)

        preferences.setDynamicPagesEnabled(false)

        #expect(!NotchPreferences(defaults: defaults).dynamicPagesEnabled)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func pagePreferencesPersistOrderAndVisibility() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)

        preferences.setVisible(.agents, isVisible: false)
        preferences.setDynamicPagesEnabled(true)
        preferences.movePages(from: IndexSet(integer: 3), to: 0)
        preferences.moveSummaryPriorities(from: IndexSet(integer: 2), to: 0)
        preferences.setShortcut(AppShortcut(key: "g", modifiers: [.command, .option]), for: .firstPage)
        preferences.setCalendarReminderLeadTimeMinutes(5)
        preferences.setTransientSystemActivityDurationSeconds(6)
        preferences.setShowChargingActivity(false)
        preferences.setShowVolumeActivity(false)
        preferences.setShowBrightnessActivity(false)
        preferences.setShowBluetoothHeadphonesActivity(false)
        preferences.setShowDownloads(false)
        preferences.setShowHomebrewDownloads(false)
        preferences.setDownloadsDirectoryURL(URL(fileURLWithPath: "/tmp/PulseNotchDownloads", isDirectory: true))
        #expect(preferences.addMonitoredGitHubRepository(named: "paugarcia32/pulse-notch"))
        #expect(!preferences.addMonitoredGitHubRepository(named: "PAUGARCiA32/PULSE-NOTCH"))
        #expect(!preferences.addMonitoredGitHubRepository(named: "not-a-repository"))
        preferences.setPreferredDisplayID("42")
        preferences.setCollapsedIndicatorMaximumPerSide(4)
        preferences.moveCollapsedIndicatorPriorities(from: IndexSet(integer: 6), to: 0)
        preferences.setCollapsedIndicatorCategory(.githubActions, isVisible: false)
        preferences.setTestingFeaturesEnabled(true)
        preferences.triggerTestingSystemActivity(.volume)

        let restoredPreferences = NotchPreferences(defaults: defaults)
        #expect(restoredPreferences.pageOrder == [.github, .summary, .calendar, .agents, .media, .clock, .downloads, .aiAgent])
        #expect(restoredPreferences.orderedVisiblePages == [.github, .summary, .calendar, .media, .clock, .downloads])
        #expect(restoredPreferences.dynamicPagesEnabled)
        #expect(restoredPreferences.summaryPriorityOrder == [.media, .calendarEvent, .githubAttention, .openPullRequest, .clock, .usageLimits])
        restoredPreferences.setActiveDynamicPages(restoredPreferences.orderedVisiblePages)
        #expect(restoredPreferences.page(for: .firstPage) == .github)
        #expect(restoredPreferences.shortcut(for: .firstPage).displayName == "⌥⌘G")
        #expect(restoredPreferences.calendarReminderLeadTimeMinutes == 5)
        #expect(restoredPreferences.calendarReminderLeadTime == 5 * 60)
        #expect(restoredPreferences.transientSystemActivityDurationSeconds == 6)
        #expect(!restoredPreferences.showChargingActivity)
        #expect(!restoredPreferences.showVolumeActivity)
        #expect(!restoredPreferences.showBrightnessActivity)
        #expect(!restoredPreferences.showBluetoothHeadphonesActivity)
        #expect(!restoredPreferences.showDownloads)
        #expect(!restoredPreferences.showHomebrewDownloads)
        #expect(restoredPreferences.downloadsDirectoryPath == "/tmp/PulseNotchDownloads")
        #expect(restoredPreferences.monitoredGitHubRepositories.map(\.nameWithOwner) == ["paugarcia32/pulse-notch"])
        #expect(restoredPreferences.preferredDisplayID == "42")
        #expect(restoredPreferences.collapsedIndicatorMaximumPerSide == 4)
        #expect(restoredPreferences.collapsedIndicatorPriorityOrder == [.codingAgents, .aiAgent, .mediaPlayback, .clock, .calendar, .githubActions, .downloads])
        #expect(!restoredPreferences.isCollapsedIndicatorCategoryVisible(.githubActions))
        #expect(restoredPreferences.isCollapsedIndicatorCategoryVisible(.calendar))
        #expect(restoredPreferences.isCollapsedIndicatorCategoryVisible(.codingAgents))
        #expect(restoredPreferences.isCollapsedIndicatorCategoryEnabled(.codingAgents))
        #expect(restoredPreferences.testingFeaturesEnabled)
        #expect(preferences.testingSystemActivity == .volume)
        #expect(preferences.testingSystemActivityTrigger != nil)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func dynamicPageShortcutsFollowCurrentlyActivePages() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)
        preferences.setActiveDynamicPages([.downloads])

        #expect(preferences.page(for: .firstPage) == .downloads)
        #expect(preferences.page(for: .secondPage) == nil)
        #expect(preferences.shortcutPages == [.downloads])

        preferences.setDynamicPagesEnabled(false)
        #expect(preferences.page(for: .firstPage) == .summary)
        #expect(preferences.page(for: .seventhPage) == .downloads)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func shortcutTitlesIncludeTheLastConfiguredPageWithoutCrashing() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)

        #expect(preferences.shortcutTitle(for: .firstPage) == "Page 1: Summary")
        #expect(preferences.shortcutTitle(for: .seventhPage) == "Page 7: Downloads")

        preferences.setVisible(.downloads, isVisible: false)
        #expect(preferences.shortcutTitle(for: .sixthPage) == "Page 6: Clock")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func aiAgentPageAppearsOnlyWhileEnabledAndTakesTheEighthShortcut() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)
        preferences.setDynamicPagesEnabled(false)

        #expect(!preferences.aiAgentEnabled)
        #expect(!preferences.orderedVisiblePages.contains(.aiAgent))
        #expect(!preferences.shortcutActions.contains(.agentEmergencyStop))
        #expect(preferences.page(for: .eighthPage) == nil)

        preferences.setAIAgentEnabled(true)
        #expect(preferences.orderedVisiblePages.last == .aiAgent)
        #expect(preferences.page(for: .eighthPage) == .aiAgent)
        #expect(preferences.shortcutTitle(for: .eighthPage) == "Page 8: AI Agent")
        #expect(preferences.shortcut(for: .eighthPage).displayName == "⌘8")
        #expect(preferences.shortcutActions.last == .agentEmergencyStop)
        #expect(preferences.shortcut(for: .agentEmergencyStop).displayName == "⌃⌥⌘.")
        #expect(ShortcutAction.agentEmergencyStop.isGlobal)
        #expect(!ShortcutAction.eighthPage.isGlobal)

        #expect(NotchPreferences(defaults: defaults).aiAgentEnabled)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func existingPageSelectionsGainTheAIAgentPageAndIndicator() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(["summary", "calendar", "agents", "github", "media", "clock", "downloads"], forKey: "settings.visiblePages")
        defaults.set(["calendar", "codingAgents"], forKey: "settings.visibleCollapsedIndicatorCategories")
        for key in ["mediaPageIntroduced", "summaryPageIntroduced", "clockPageIntroduced", "downloadsPageIntroduced",
                    "mediaCollapsedIndicatorIntroduced", "clockCollapsedIndicatorIntroduced"] {
            defaults.set(true, forKey: "settings.\(key)")
        }

        let preferences = NotchPreferences(defaults: defaults)

        #expect(preferences.isVisible(.aiAgent))
        #expect(preferences.pageOrder.last == .aiAgent)
        #expect(preferences.isCollapsedIndicatorCategoryVisible(.aiAgent))
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func githubRepositoryPreferencesCanDisconnectARepository() throws {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)
        let repository = try #require(GitHubRepository(nameWithOwner: "example/project"))

        #expect(preferences.addMonitoredGitHubRepository(named: repository.nameWithOwner))
        preferences.removeMonitoredGitHubRepository(repository)

        #expect(NotchPreferences(defaults: defaults).monitoredGitHubRepositories.isEmpty)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func existingPreferencesEnableNewPagesOnce() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set([NotchPage.calendar.rawValue], forKey: "settings.visiblePages")
        defaults.set(true, forKey: "settings.mediaPageIntroduced")
        defaults.set(true, forKey: "settings.summaryPageIntroduced")

        _ = NotchPreferences(defaults: defaults)
        let restoredPreferences = NotchPreferences(defaults: defaults)

        #expect(restoredPreferences.orderedVisiblePages == [.calendar, .clock, .downloads])

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func pageAndClosedNotchActivityVisibilityAreIndependent() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)

        preferences.setVisible(.agents, isVisible: false)

        #expect(preferences.isCollapsedIndicatorCategoryVisible(.codingAgents))
        #expect(preferences.isCollapsedIndicatorCategoryEnabled(.codingAgents))
        #expect(preferences.isCollapsedIndicatorCategoryVisible(.downloads))

        preferences.setCollapsedIndicatorCategory(.codingAgents, isVisible: false)

        #expect(!preferences.isCollapsedIndicatorCategoryVisible(.codingAgents))
        #expect(!preferences.isCollapsedIndicatorCategoryEnabled(.codingAgents))

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func closedNotchActivitiesDeclareTheirOwningPage() {
        #expect(CollapsedNotchIndicatorCategory.calendar.ownerPage == .calendar)
        #expect(CollapsedNotchIndicatorCategory.codingAgents.ownerPage == .agents)
        #expect(CollapsedNotchIndicatorCategory.githubActions.ownerPage == .github)
        #expect(CollapsedNotchIndicatorCategory.mediaPlayback.ownerPage == .media)
        #expect(CollapsedNotchIndicatorCategory.clock.ownerPage == .clock)
        #expect(CollapsedNotchIndicatorCategory.downloads.ownerPage == .downloads)
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

    @Test
    func closedNotchColorsPersistAndCanBeRestoredToDefaults() {
        let suiteName = "PulseNotchTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = NotchPreferences(defaults: defaults)

        preferences.setCollapsedIndicatorColor(.yellow, for: .calendar)

        let restoredPreferences = NotchPreferences(defaults: defaults)
        #expect(restoredPreferences.hasCustomCollapsedIndicatorColors)
        #expect(restoredPreferences.customCollapsedIndicatorColor(for: .calendar) != nil)
        #expect(restoredPreferences.customCollapsedIndicatorColor(for: .downloads) == nil)

        restoredPreferences.resetCollapsedIndicatorColors()

        let defaultPreferences = NotchPreferences(defaults: defaults)
        #expect(!defaultPreferences.hasCustomCollapsedIndicatorColors)
        #expect(defaultPreferences.customCollapsedIndicatorColor(for: .calendar) == nil)

        defaults.removePersistentDomain(forName: suiteName)
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

private struct GitHubProviderFake: GitHubActivityProviding {
    let fails: Bool
    let providedActivity: GitHubActivitySnapshot

    init(
        fails: Bool = false,
        activity: GitHubActivitySnapshot = .init(pullRequests: [], actionRuns: [])
    ) {
        self.fails = fails
        providedActivity = activity
    }

    func activity(repositories: [GitHubRepository]) async throws -> GitHubActivitySnapshot {
        if fails { throw CocoaError(.fileReadUnknown) }
        return providedActivity
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

private struct MediaPlaybackProviderFake: MediaPlaybackProviding {
    let playback: MediaPlaybackStatus?

    func currentPlayback() async throws -> MediaPlaybackStatus? { playback }
    func send(_ command: MediaPlaybackCommand) async throws {}
}

@MainActor
private final class MediaPlaybackCommandProvider: MediaPlaybackProviding, @unchecked Sendable {
    private var playback: MediaPlaybackStatus
    private(set) var commands: [MediaPlaybackCommand] = []

    init(playback: MediaPlaybackStatus) {
        self.playback = playback
    }

    func currentPlayback() async throws -> MediaPlaybackStatus? { playback }

    func send(_ command: MediaPlaybackCommand) async throws {
        commands.append(command)
        if command == .togglePlayPause {
            playback = MediaPlaybackStatus(
                id: playback.id,
                title: playback.title,
                artist: playback.artist,
                duration: playback.duration,
                elapsedTime: playback.elapsedTime,
                isPlaying: !playback.isPlaying
            )
        }
    }
}

private actor BluetoothHeadphonesSequenceProvider: BluetoothHeadphonesProviding {
    private var statuses: [[BluetoothHeadphonesStatus]]

    init(statuses: [[BluetoothHeadphonesStatus]]) {
        self.statuses = statuses
    }

    func connectedHeadphones() async throws -> [BluetoothHeadphonesStatus] {
        statuses.removeFirst()
    }
}

private actor DownloadSequenceProvider: DownloadsProviding {
    private var snapshots: [[DetectedDownload]]

    init(snapshots: [[DetectedDownload]]) {
        self.snapshots = snapshots
    }

    func activeDownloads(in directory: URL, includeHomebrew: Bool) async throws -> [DetectedDownload] {
        snapshots.removeFirst()
    }
}
