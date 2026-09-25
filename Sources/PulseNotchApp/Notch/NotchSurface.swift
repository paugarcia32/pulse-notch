import PulseNotchCore
import SwiftUI

struct NotchSurface: View {
    @ObservedObject var calendarModel: CalendarFeatureModel
    @ObservedObject var codingAgentModel: CodingAgentFeatureModel
    @ObservedObject var gitHubModel: GitHubFeatureModel
    @ObservedObject var batteryModel: BatteryFeatureModel
    @ObservedObject var volumeModel: VolumeFeatureModel
    @ObservedObject var brightnessModel: BrightnessFeatureModel
    @ObservedObject var downloadModel: DownloadFeatureModel
    @ObservedObject var mediaPlaybackModel: MediaPlaybackFeatureModel
    @ObservedObject var clockModel: ClockFeatureModel
    let bluetoothHeadphonesModel: BluetoothHeadphonesFeatureModel
    @ObservedObject var systemActivityModel: SystemActivityFeatureModel
    @ObservedObject var preferences: NotchPreferences
    @ObservedObject var updateModel: UpdateFeatureModel
    @ObservedObject var homebrewUpdate: HomebrewUpdateCoordinator
    @ObservedObject var aiAgentModel: AIAgentFeatureModel
    @ObservedObject var computerUsePermissions: ComputerUsePermissions
    let physicalNotchSize: CGSize?
    let collapsedSize: CGSize
    let expandedSize: CGSize
    /// The larger surface used by the AI Agent page.
    let aiAgentExpandedSize: CGSize
    let onExpansionChanged: (Bool) -> Void
    /// Lets the panel controller size the window for the selected page.
    let onPageChanged: (NotchPage) -> Void
    @State private var isExpanded = false
    @State private var expansionProgress: CGFloat = 0
    @State private var selectedPage = NotchPage.summary
    @State private var pageDragOffset: CGFloat = 0
    @State private var isHoveringPageIndicator = false
    @State private var hoverState = NotchHoverState()
    @State private var hoverTask: Task<Void, Never>?
    @State private var hoverRearmTask: Task<Void, Never>?
    @State private var transitionTask: Task<Void, Never>?
    @State private var systemActivityTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct TestingPreviewData {
        let schedule: CalendarEventSchedule?
        let sessions: [CodingAgentSession]?
        let actions: [GitHubActionSession]?
        let pullRequests: [GitHubPullRequest]?
        let usage: [CodingAgentUsageAvailability]?
        let downloads: [DetectedDownload]?
        let media: MediaPlaybackStatus?
        let clock: ClockStatus?

        var hasGitHubActivity: Bool {
            !(actions ?? []).isEmpty || !(pullRequests ?? []).isEmpty
        }

        @MainActor
        static func make(preferences: NotchPreferences, at date: Date) -> Self {
            guard preferences.testingFeaturesEnabled else {
                return Self(
                    schedule: nil,
                    sessions: nil,
                    actions: nil,
                    pullRequests: nil,
                    usage: nil,
                    downloads: nil,
                    media: nil,
                    clock: nil
                )
            }

            let schedule = (0..<preferences.collapsedIndicatorPreviewCount(.calendar)).compactMap {
                CollapsedIndicatorPreview.calendar.testingCalendarEvent(instance: $0, at: date)
            }
            let sessions = CollapsedIndicatorPreview.allCases.flatMap { preview in
                (0..<preferences.collapsedIndicatorPreviewCount(preview)).compactMap {
                    preview.testingAgentSession(instance: $0, at: date)
                }
            }
            let actions = (0..<preferences.collapsedIndicatorPreviewCount(.githubActions)).compactMap {
                CollapsedIndicatorPreview.githubActions.testingActionSession(instance: $0, at: date)
            }
            let downloads = (0..<preferences.collapsedIndicatorPreviewCount(.download)).compactMap {
                CollapsedIndicatorPreview.download.testingDownload(instance: $0)
            }
            let pullRequests: [GitHubPullRequest] = SummaryPreview.allCases.compactMap { preview in
                guard preferences.summaryPreviewCount(preview) > 0 else { return nil }
                return preview.testingPullRequest(at: date)
            }
            let usage: [CodingAgentUsageAvailability] = SummaryPreview.allCases.reduce(into: []) { result, preview in
                guard preferences.summaryPreviewCount(preview) > 0 else { return }
                result += preview.testingUsage(at: date) ?? []
            }
            let media = preferences.collapsedIndicatorPreviewCount(.mediaPlayback) > 0
                ? CollapsedIndicatorPreview.mediaPlayback.testingPlayback()
                : nil
            let clock = preferences.collapsedIndicatorPreviewCount(.clock) > 0
                ? CollapsedIndicatorPreview.clock.testingClockStatus()
                : nil
            return Self(
                schedule: schedule.isEmpty ? nil : CalendarEventSchedule(events: schedule),
                sessions: sessions.isEmpty ? nil : sessions,
                actions: actions.isEmpty ? nil : actions,
                pullRequests: pullRequests.isEmpty ? nil : pullRequests,
                usage: usage.isEmpty ? nil : usage,
                downloads: downloads.isEmpty ? nil : downloads,
                media: media,
                clock: clock
            )
        }
    }

    /// The expanded size for the selected page. The window can be briefly larger
    /// while it shrinks after leaving a larger page, so content stays top-aligned.
    private var currentExpandedSize: CGSize {
        selectedPage == .aiAgent ? aiAgentExpandedSize : expandedSize
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            activitySurface
                .frame(width: currentExpandedSize.width, height: currentExpandedSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .windowResizeBehavior(.disabled)
        } else {
            activitySurface
                .frame(width: currentExpandedSize.width, height: currentExpandedSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var navigationSurface: some View {
        refreshingSurface
        .onChange(of: codingAgentModel.state) { _, _ in
            acknowledgeCompletedActivity()
        }
        .onChange(of: gitHubModel.actionSessions) { _, _ in
            acknowledgeCompletedActivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchOpenSurface)) { _ in openNotch() }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchClose)) { _ in closeNotch() }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowSummary)) { _ in
            openNotch()
            selectPage(.summary)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowCalendar)) { _ in
            openNotch()
            selectPage(.calendar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowAgents)) { _ in
            openNotch()
            selectPage(.agents)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowGitHub)) { _ in
            openNotch()
            selectPage(.github)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowMedia)) { _ in
            openNotch()
            selectPage(.media)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowClock)) { _ in
            openNotch()
            selectPage(.clock)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowDownloads)) { _ in
            openNotch()
            selectPage(.downloads)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowAIAgent)) { _ in
            openNotch()
            selectPage(.aiAgent)
        }
        .onChange(of: selectedPage) { _, page in onPageChanged(page) }
        .onAppear { onPageChanged(selectedPage) }
        .onChange(of: preferences.orderedVisiblePages) { _, _ in
            handleVisiblePagesChange(displayedPages(at: .now))
        }
        .onChange(of: preferences.dynamicPagesEnabled) { _, _ in
            handleVisiblePagesChange(displayedPages(at: .now))
        }
    }

    private var activitySurface: some View {
        navigationSurface
        .onChange(of: batteryModel.chargingActivity) { _, activity in handleChargingActivity(activity) }
        .onChange(of: volumeModel.activity) { _, activity in handleVolumeActivity(activity) }
        .onChange(of: brightnessModel.activity) { _, activity in handleBrightnessActivity(activity) }
        .onChange(of: preferences.testingSystemActivityTrigger) { _, _ in
            showTestingSystemActivity()
        }
        .onChange(of: systemActivityModel.activity) { _, activity in scheduleSystemActivityDismissal(activity) }
        .onChange(of: preferences.showChargingActivity) { _, isShown in dismissSystemActivity(.charging, when: !isShown) }
        .onChange(of: preferences.showVolumeActivity) { _, isShown in dismissSystemActivity(.volume(isMuted: false), when: !isShown) }
        .onChange(of: preferences.showBrightnessActivity) { _, isShown in dismissSystemActivity(.brightness, when: !isShown) }
        .onChange(of: preferences.showBluetoothHeadphonesActivity) { _, isShown in dismissSystemActivity(.bluetoothHeadphones(batteryLevel: nil), when: !isShown) }
        .onDisappear {
            systemActivityTask?.cancel()
            hoverTask?.cancel()
            hoverRearmTask?.cancel()
            transitionTask?.cancel()
            volumeModel.stopMonitoring()
            brightnessModel.stopMonitoring()
            downloadModel.stopMonitoring()
        }
    }

    private var refreshingSurface: some View {
        surface
        .task(id: calendarMonitoringEnabled) {
            guard calendarMonitoringEnabled else { return }
            while !Task.isCancelled {
                await calendarModel.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: preferences.showBluetoothHeadphonesActivity) {
            guard preferences.showBluetoothHeadphonesActivity else { return }
            // Connection state is public through IOBluetooth. Polling avoids an
            // Objective-C callback lifetime while keeping HUD latency below one second.
            while !Task.isCancelled {
                if let activity = await bluetoothHeadphonesModel.refresh() {
                    handleBluetoothHeadphonesActivity(activity)
                }
                try? await Task.sleep(for: bluetoothHeadphonesModel.hasPendingBattery ? .milliseconds(100) : .seconds(1))
            }
        }
        .task(id: downloadsMonitoringID) {
            guard preferences.showDownloads else {
                downloadModel.stopMonitoring()
                return
            }
            await downloadModel.startMonitoring(
                directory: preferences.downloadsDirectoryURL,
                includeHomebrew: preferences.showHomebrewDownloads
            )
            // ponytail: scan once per second. Browser downloads have no public
            // system-wide activity API; use a file-system event source only if
            // polling proves measurably too expensive.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await downloadModel.refresh()
            }
        }
        .task { await volumeModel.startMonitoring() }
        .task(id: preferences.showBrightnessActivity) {
            if preferences.showBrightnessActivity {
                brightnessModel.startMonitoring()
            } else {
                brightnessModel.stopMonitoring()
            }
        }
        .task(id: gitHubMonitoringID) {
            guard gitHubMonitoringEnabled else { return }
            while !Task.isCancelled {
                await gitHubModel.refresh(repositories: preferences.monitoredGitHubRepositories)
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: codingAgentsMonitoringEnabled) {
            guard codingAgentsMonitoringEnabled else { return }
            while !Task.isCancelled {
                await codingAgentModel.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .task {
            // ponytail: one-second polling is enough for system HUD timing; use IOKit notifications only if it proves insufficient.
            while !Task.isCancelled {
                await batteryModel.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: mediaMonitoringEnabled) {
            guard mediaMonitoringEnabled else { return }
            while !Task.isCancelled {
                await mediaPlaybackModel.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: usageMonitoringEnabled) {
            guard usageMonitoringEnabled else { return }
            while !Task.isCancelled {
                await codingAgentModel.refreshUsage()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var surface: some View {
        TimelineView(.periodic(from: .now, by: clockModel.isRunning ? 1 : 15)) { context in
            let pages = displayedPages(at: context.date)
            notch(at: context.date, pages: pages)
                .onAppear { handleVisiblePagesChange(pages) }
                .onChange(of: pages) { _, pages in handleVisiblePagesChange(pages) }
        }
    }

    private func handleChargingActivity(_ activity: BatteryFeatureModel.ChargingActivity?) {
        guard let activity else { return }
        if preferences.showChargingActivity {
            systemActivityModel.present(kind: .charging, level: activity.chargeLevel)
        }
        batteryModel.dismissChargingActivity(id: activity.id)
    }

    private func handleVisiblePagesChange(_ pages: [NotchPage]) {
        preferences.setActiveDynamicPages(pages)
        if !pages.contains(selectedPage), let firstPage = pages.first {
            selectedPage = firstPage
            pageDragOffset = 0
        }
    }

    private func acknowledgeCompletedActivity() {
        guard isExpanded else { return }
        codingAgentModel.acknowledgeCompletedSessions()
        gitHubModel.acknowledgeCompletedActions()
    }

    private func handleVolumeActivity(_ activity: SystemVolumeStatus?) {
        guard let activity else { return }
        if preferences.showVolumeActivity {
            systemActivityModel.present(kind: .volume(isMuted: activity.isMuted), level: activity.level)
        }
        volumeModel.consumeActivity()
    }

    private func handleBrightnessActivity(_ activity: DisplayBrightnessStatus?) {
        guard let activity else { return }
        if preferences.showBrightnessActivity {
            systemActivityModel.present(kind: .brightness, level: activity.level)
        }
        brightnessModel.consumeActivity()
    }

    private func handleBluetoothHeadphonesActivity(_ activity: BluetoothHeadphonesStatus) {
        if preferences.showBluetoothHeadphonesActivity {
            systemActivityModel.present(kind: .bluetoothHeadphones(batteryLevel: activity.batteryLevel), level: activity.batteryLevel ?? 0)
        }
    }

    private func showTestingSystemActivity() {
        switch preferences.testingSystemActivity {
        case .charging where preferences.showChargingActivity:
            systemActivityModel.present(kind: .charging, level: 72)
        case .volume where preferences.showVolumeActivity:
            systemActivityModel.present(kind: .volume(isMuted: false), level: 64)
        case .brightness where preferences.showBrightnessActivity:
            systemActivityModel.present(kind: .brightness, level: 72)
        case .bluetoothHeadphones where preferences.showBluetoothHeadphonesActivity:
            systemActivityModel.present(kind: .bluetoothHeadphones(batteryLevel: 72), level: 72)
        case nil, .charging, .volume, .brightness, .bluetoothHeadphones:
            break
        }
    }

    private func notch(at date: Date, pages: [NotchPage]) -> some View {
        let currentIndicators = indicators(at: date)
        let collapsedSurfaceSize = collapsedSurfaceSize(for: currentIndicators)

        return ZStack(alignment: .top) {
            notchBackground(collapsedSize: collapsedSurfaceSize)

            expandedContent(at: date, pages: pages)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(width: currentExpandedSize.width, height: currentExpandedSize.height, alignment: .top)
                .opacity(expansionProgress)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
                .onHover { hovering in
                    guard shouldHandleHover(from: .expanded, isExpanded: isExpanded) else { return }
                    handleHover(hovering)
                }

            collapsedIndicators(at: date)
                .padding(.horizontal, physicalNotchSize == nil && systemActivityModel.activity == nil ? 12 : 0)
                .frame(width: collapsedSurfaceSize.width, height: collapsedSurfaceSize.height, alignment: .top)
                .opacity(1 - expansionProgress)
                .allowsHitTesting(!isExpanded)
                .accessibilityHidden(isExpanded)
        }
        .overlay(alignment: .top) {
            if !isExpanded {
                Color.clear
                    .frame(
                        width: physicalNotchSize?.width ?? collapsedSize.width,
                        height: physicalNotchSize?.height ?? collapsedSize.height
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        guard shouldHandleHover(from: .collapsed, isExpanded: isExpanded) else { return }
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        hoverState.update(isHovering: true)
                        openNotch()
                    }
            }
        }
        .foregroundStyle(.white)
        .frame(width: currentExpandedSize.width, height: currentExpandedSize.height, alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: systemActivityModel.activity)
        .onChange(of: isExpanded) { _, isOpen in
            if isOpen { NotchHapticFeedback.performOpen() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pulse Notch")
    }

    @ViewBuilder
    private func collapsedIndicators(at date: Date) -> some View {
        if let activity = systemActivityModel.activity {
            systemActivity(activity)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.98))
                            .animation(.smooth(duration: 0.35)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.995))
                            .animation(.easeOut(duration: 0.28))
                    )
                )
        } else {
            let currentIndicators = indicators(at: date)
            if let physicalNotchSize {
                physicalNotchIndicators(currentIndicators, notchSize: physicalNotchSize)
            } else if case let .mediaPlayback(playback) = currentIndicators.first?.content {
                HStack(spacing: 10) {
                    MediaArtworkView(data: playback.artworkData, size: 22)
                    Spacer(minLength: 0)
                    MediaEqualizer(isPlaying: playback.isPlaying, reduceMotion: reduceMotion)
                        .foregroundStyle(collapsedIndicatorColor(for: currentIndicators[0]))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(currentIndicators[0].accessibilityLabel)
            } else if case let .clock(status) = currentIndicators.first?.content {
                ClockCollapsedIndicator(
                    status: status,
                    color: collapsedIndicatorColor(for: currentIndicators[0]),
                    reduceMotion: reduceMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(currentIndicators[0].accessibilityLabel)
            } else {
                HStack(spacing: 8) {
                    ForEach(currentIndicators.prefix(5)) {
                        NotchIndicatorView(
                            indicator: $0,
                            reduceMotion: reduceMotion,
                            colorOverride: collapsedIndicatorColorOverride(for: $0)
                        )
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func systemActivity(_ activity: SystemActivityFeatureModel.Activity) -> some View {
        if let physicalNotchSize {
            HStack(spacing: 0) {
                Image(systemName: activity.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(activity.color)
                    .frame(width: systemActivitySideWidth, height: physicalNotchSize.height)

                Color.clear
                    .frame(width: physicalNotchSize.width, height: physicalNotchSize.height)
                    .accessibilityHidden(true)

                activityLevel(activity)
                    .frame(width: systemActivitySideWidth, height: physicalNotchSize.height)
            }
            .frame(width: physicalNotchSize.width + 2 * systemActivitySideWidth, height: physicalNotchSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.accessibilityLabel)
        } else {
            HStack(spacing: 0) {
                Image(systemName: activity.symbolName)
                    .frame(width: systemActivitySideWidth, height: collapsedSize.height)

                Color.clear
                    .frame(width: SystemActivityLayout.externalCenterWidth(for: collapsedSize.width), height: collapsedSize.height)
                    .accessibilityHidden(true)

                activityLevel(activity)
                    .frame(width: systemActivitySideWidth, height: collapsedSize.height)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(activity.color)
            .frame(width: collapsedSize.width, height: collapsedSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.accessibilityLabel)
        }
    }

    private var systemActivitySideWidth: CGFloat { SystemActivityLayout.sideWidth }

    @ViewBuilder
    private func activityLevel(_ activity: SystemActivityFeatureModel.Activity) -> some View {
        if let trailingSymbolName = activity.trailingSymbolName {
            Image(systemName: trailingSymbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(activity.trailingColor)
        } else if activity.showsCircularLevel {
            ActivityLevelRing(level: activity.level, color: activity.color, reduceMotion: reduceMotion)
        } else {
            Text("\(activity.level)%")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(activity.color)
        }
    }

    private func physicalNotchIndicators(_ indicators: [NotchIndicator], notchSize: CGSize) -> some View {
        let layout = CollapsedNotchLayout(
            indicators: indicators,
            maximumPerSide: preferences.collapsedIndicatorMaximumPerSide
        )
        let sideWidth = collapsedSideWidth(for: layout.levels)

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Array(layout.levels.enumerated().reversed()), id: \.offset) { _, level in
                    collapsedIndicator(level.left, side: .left)
                        .frame(width: level.width, alignment: .trailing)
                }
            }
            .padding(.leading, NotchSurfaceSize.collapsedIndicatorOuterPadding)
            .padding(.trailing, NotchSurfaceSize.physicalNotchContentSpacing)
            .frame(width: sideWidth, height: notchSize.height, alignment: .trailing)

            Color.clear
                .frame(width: notchSize.width, height: notchSize.height)
                .accessibilityHidden(true)

            HStack(spacing: 8) {
                ForEach(Array(layout.levels.enumerated()), id: \.offset) { _, level in
                    collapsedIndicator(level.right, side: .right)
                        .frame(width: level.width, alignment: .leading)
                }
            }
            .padding(.leading, NotchSurfaceSize.physicalNotchContentSpacing)
            .padding(.trailing, NotchSurfaceSize.collapsedIndicatorOuterPadding)
            .frame(width: sideWidth, height: notchSize.height, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum CollapsedIndicatorSide {
        case left
        case right
    }

    @ViewBuilder
    private func collapsedIndicator(_ indicator: NotchIndicator?, side: CollapsedIndicatorSide) -> some View {
        if let indicator {
            switch (indicator.content, side) {
            case (.upcomingCalendarEvent, .left):
                CalendarCountdownIcon(color: collapsedIndicatorColor(for: indicator))
                    .accessibilityLabel(indicator.accessibilityLabel)
            case let (.upcomingCalendarEvent(minutesUntilStart), .right):
                CalendarCountdownValue(minutesUntilStart: minutesUntilStart, reduceMotion: reduceMotion)
                    .foregroundStyle(collapsedIndicatorColor(for: indicator))
                    .accessibilityHidden(true)
            case let (.runningDownload(percentage), .left):
                DownloadProgressValue(
                    percentage: percentage,
                    color: collapsedIndicatorColor(for: indicator),
                    reduceMotion: reduceMotion
                )
                .accessibilityLabel(indicator.accessibilityLabel)
            case (.runningDownload, .right):
                DownloadActivityIndicator(
                    color: collapsedIndicatorColor(for: indicator),
                    reduceMotion: reduceMotion
                )
                .accessibilityHidden(true)
            case let (.mediaPlayback(playback), .left):
                MediaArtworkView(data: playback.artworkData, size: 22)
                    .accessibilityLabel(indicator.accessibilityLabel)
            case let (.mediaPlayback(playback), .right):
                MediaEqualizer(isPlaying: playback.isPlaying, reduceMotion: reduceMotion)
                    .foregroundStyle(collapsedIndicatorColor(for: indicator))
                    .accessibilityHidden(true)
            case let (.clock(status), .left):
                Image(systemName: status.mode.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(collapsedIndicatorColor(for: indicator))
                    .accessibilityLabel(indicator.accessibilityLabel)
            case let (.clock(status), .right):
                ClockCollapsedValue(status: status, reduceMotion: reduceMotion)
                    .foregroundStyle(collapsedIndicatorColor(for: indicator))
                    .accessibilityHidden(true)
            default:
                NotchIndicatorView(
                    indicator: indicator,
                    reduceMotion: reduceMotion,
                    colorOverride: collapsedIndicatorColorOverride(for: indicator)
                )
            }
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }

    private func collapsedSideWidth(for levels: [CollapsedNotchLayout.Level]) -> CGFloat {
        guard !levels.isEmpty else { return 0 }
        return levels.map(\.width).reduce(0, +)
            + CGFloat(levels.count - 1) * 8
            + NotchSurfaceSize.collapsedIndicatorOuterPadding
            + NotchSurfaceSize.physicalNotchContentSpacing
    }

    private func collapsedSurfaceSize(for indicators: [NotchIndicator]) -> CGSize {
        guard let physicalNotchSize else { return collapsedSize }
        if systemActivityModel.activity != nil {
            return CGSize(
                width: physicalNotchSize.width + 2 * systemActivitySideWidth,
                height: physicalNotchSize.height
            )
        }
        let layout = CollapsedNotchLayout(
            indicators: indicators,
            maximumPerSide: preferences.collapsedIndicatorMaximumPerSide
        )
        return CGSize(
            width: physicalNotchSize.width + 2 * collapsedSideWidth(for: layout.levels),
            height: physicalNotchSize.height
        )
    }

    private func collapsedIndicatorColor(for indicator: NotchIndicator) -> Color {
        collapsedIndicatorColorOverride(for: indicator) ?? indicator.color
    }

    private func collapsedIndicatorColorOverride(for indicator: NotchIndicator) -> Color? {
        guard indicator.supportsCustomColor else { return nil }
        return preferences.customCollapsedIndicatorColor(for: indicator.category)
    }

    private func expandedContent(at date: Date, pages: [NotchPage]) -> some View {
        let showsPageIndicator = shouldShowPageIndicator(for: pages)

        return Group {
            if pages.isEmpty {
                Label("No active pages", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHint("Pages will appear when new activity starts")
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(pages) { page in
                            pageContent(page, at: date, availablePages: Set(pages))
                                .frame(width: geometry.size.width)
                                .accessibilityHidden(selectedPage != page)
                        }
                    }
                    .offset(x: -CGFloat(selectedPageIndex(in: pages)) * geometry.size.width + pageDragOffset)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: pages)
        .clipped()
        .padding(.top, max(physicalNotchSize?.height ?? 0, showsPageIndicator ? 18 : 0))
        .overlay(alignment: .topLeading) {
            if let release = updateModel.availableRelease {
                updateNotice(for: release)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsPageIndicator {
                pageIndicator(pages: pages)
            }
        }
        .contentShape(Rectangle())
        .background {
            TrackpadSwipeDetector {
                // Horizontal swipes on the AI Agent page would fight text selection and scrolling.
                guard selectedPage != .aiAgent else { return }
                selectPage($0 == .left ? nextPage(in: pages) : previousPage(in: pages), in: pages)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged {
                    guard abs($0.translation.width) > abs($0.translation.height) else { return }
                    pageDragOffset = $0.translation.width
                }
                .onEnded {
                    guard abs($0.translation.width) > abs($0.translation.height) else {
                        selectPage(selectedPage, in: pages)
                        return
                    }
                    selectPage($0.translation.width < 0 ? nextPage(in: pages) : previousPage(in: pages), in: pages)
                },
            including: selectedPage == .aiAgent ? .subviews : .all
        )
    }

    private func updateNotice(for release: AppRelease) -> some View {
        Button {
            homebrewUpdate.install(release)
        } label: {
            Label("Ready to update", systemImage: "shippingbox")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .frame(
                    maxWidth: max(0, (currentExpandedSize.width - (physicalNotchSize?.width ?? 0)) / 2 - 18),
                    alignment: .leading
                )
        }
        .buttonStyle(.plain)
        .disabled(homebrewUpdate.isPreparing)
        .accessibilityLabel("Update Pulse Notch to version \(release.version.description)")
        .accessibilityHint("Updates with Homebrew when available, otherwise opens the release page")
    }

    private func pageIndicator(pages: [NotchPage]) -> some View {
        HStack(spacing: -3) {
            ForEach(pages) { page in
                Button { selectPage(page, in: pages) } label: {
                    Circle()
                        .fill(page == selectedPage ? .white : .white.opacity(0.35))
                        .frame(
                            width: page == selectedPage ? indicatorSize + 2 : indicatorSize,
                            height: page == selectedPage ? indicatorSize + 2 : indicatorSize
                        )
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(page.name) page")
                .accessibilityAddTraits(page == selectedPage ? .isSelected : [])
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.16)) {
                isHoveringPageIndicator = hovering
            }
        }
    }

    private var indicatorSize: CGFloat { isHoveringPageIndicator ? 5 : 3 }

    private func notchBackground(collapsedSize: CGSize) -> some View {
        let bottomRadius = interpolated(from: 8, to: 18)
        return NotchBackgroundShape(
            size: CGSize(
                width: interpolated(from: collapsedSize.width, to: currentExpandedSize.width),
                height: interpolated(from: collapsedSize.height, to: currentExpandedSize.height)
            ),
            topRadius: 0,
            bottomRadius: bottomRadius
        )
        .fill(.black)
    }

    private func indicators(at date: Date) -> [NotchIndicator] {
        if preferences.testingFeaturesEnabled {
            let previews = CollapsedIndicatorPreview.allCases
                .flatMap { preview in
                    (0..<preferences.collapsedIndicatorPreviewCount(preview)).map {
                        preview.indicator(instance: $0, at: date)
                    }
                }
            if !previews.isEmpty {
                return CollapsedNotchIndicators.prioritize(
                    previews.filter { preferences.isCollapsedIndicatorCategoryVisible($0.category) },
                    using: preferences.collapsedIndicatorPriorityOrder
                )
            }
        }
        let schedule: CalendarEventSchedule?
        if case let .loaded(loadedSchedule) = calendarModel.state {
            schedule = loadedSchedule
        } else {
            schedule = nil
        }
        let sessions: [CodingAgentSession] = if case .loaded = codingAgentModel.state {
            codingAgentModel.notificationSessions
        } else {
            []
        }
        let indicators = CollapsedNotchIndicators.make(
            schedule: schedule,
            sessions: sessions,
            actionSessions: gitHubModel.notificationActionSessions,
            downloads: preferences.showDownloads ? downloadModel.activeDownloads : [],
            mediaPlayback: mediaPlaybackModel.playback,
            clock: clockModel.status(at: date),
            aiAgent: preferences.aiAgentEnabled ? aiAgentModel.indicatorState : nil,
            at: date,
            calendarReminderLeadTime: preferences.calendarReminderLeadTime
        ).filter { preferences.isCollapsedIndicatorCategoryVisible($0.category) }
        return CollapsedNotchIndicators.prioritize(
            indicators,
            using: preferences.collapsedIndicatorPriorityOrder
        )
    }

    private var downloadsMonitoringID: String {
        "\(preferences.showDownloads)-\(preferences.showHomebrewDownloads)-\(preferences.downloadsDirectoryPath)"
    }

    private var calendarMonitoringEnabled: Bool {
        preferences.isVisible(.calendar)
            || preferences.isVisible(.summary)
            || preferences.isCollapsedIndicatorCategoryEnabled(.calendar)
    }

    private var gitHubMonitoringEnabled: Bool {
        preferences.isVisible(.github)
            || preferences.isVisible(.summary)
            || preferences.isCollapsedIndicatorCategoryEnabled(.githubActions)
    }

    private var gitHubMonitoringID: String {
        "\(gitHubMonitoringEnabled)-\(preferences.monitoredGitHubRepositories.map(\.id).joined(separator: ","))"
    }

    private var codingAgentsMonitoringEnabled: Bool {
        preferences.isVisible(.agents)
            || preferences.isVisible(.summary)
            || preferences.isCollapsedIndicatorCategoryEnabled(.codingAgents)
    }

    private var mediaMonitoringEnabled: Bool {
        preferences.isVisible(.media)
            || preferences.isVisible(.summary)
            || preferences.isCollapsedIndicatorCategoryEnabled(.mediaPlayback)
    }

    private var usageMonitoringEnabled: Bool {
        isExpanded && (selectedPage == .agents || selectedPage == .summary)
    }

    private func scheduleSystemActivityDismissal(_ activity: SystemActivityFeatureModel.Activity?) {
        systemActivityTask?.cancel()
        guard let activity else { return }
        systemActivityTask = Task { @MainActor in
            try? await Task.sleep(for: preferences.transientSystemActivityDuration)
            guard !Task.isCancelled else { return }
            systemActivityModel.dismiss(id: activity.id)
        }
    }

    private func dismissSystemActivity(_ kind: SystemActivityFeatureModel.Kind, when condition: Bool) {
        guard condition, let activity = systemActivityModel.activity, activity.kind.matches(kind) else { return }
        systemActivityModel.dismiss(id: activity.id)
    }

    private func openNotch() {
        guard !isExpanded else { return }
        isExpanded = true
        onExpansionChanged(true)
        animateExpansion(to: 1)
        acknowledgeCompletedActivity()
    }

    private func closeNotch() {
        guard isExpanded else { return }
        isExpanded = false
        hoverState.notchClosed()
        hoverRearmTask?.cancel()
        hoverRearmTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            hoverState.finishClosing()
        }
        animateExpansion(to: 0) {
            onExpansionChanged(false)
        }
    }

    private func animateExpansion(to target: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        transitionTask?.cancel()
        guard !reduceMotion else {
            expansionProgress = target
            completion?()
            return
        }

        withAnimation(NotchMotion.animation) {
            expansionProgress = target
        }
        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(NotchMotion.duration + 1 / 60))
            guard !Task.isCancelled else { return }
            completion?()
        }
    }

    private func interpolated(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * expansionProgress
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        hoverState.update(isHovering: hovering)
        if hovering {
            guard hoverState.canOpen, !isExpanded else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                openNotch()
            }
        } else if isExpanded, selectedPage != .aiAgent {
            // The AI Agent page stays open when the pointer leaves so drafts and
            // keyboard focus survive; explicit dismissal still collapses it.
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                closeNotch()
            }
        }
    }

    private func selectPage(_ page: NotchPage, in pages: [NotchPage]? = nil) {
        let pages = pages ?? displayedPages(at: .now)
        guard pages.contains(page) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            selectedPage = page
            pageDragOffset = 0
        }
    }

    @ViewBuilder
    private func pageContent(
        _ page: NotchPage,
        at date: Date,
        availablePages: Set<NotchPage>
    ) -> some View {
        let testingData = testingPreviewData(at: date)
        switch page {
        case .summary:
            SummaryPage(
                calendarModel: calendarModel,
                codingAgentModel: codingAgentModel,
                gitHubModel: gitHubModel,
                mediaPlaybackModel: mediaPlaybackModel,
                clockModel: clockModel,
                priorities: preferences.summaryPriorityOrder,
                date: date,
                availablePages: availablePages,
                onSelectPage: { selectPage($0) },
                testingSchedule: testingData.schedule,
                testingSessions: testingData.sessions,
                testingActions: testingData.actions,
                testingPullRequests: testingData.pullRequests,
                testingUsage: testingData.usage,
                testingMedia: testingData.media,
                testingClock: testingData.clock
            )
        case .calendar: CalendarPage(model: calendarModel, date: date, testingSchedule: testingData.schedule)
        case .agents: CodingAgentsPage(model: codingAgentModel, date: date, testingSessions: testingData.sessions)
        case .github:
            GitHubPage(
                model: gitHubModel,
                date: date,
                testingPullRequests: testingData.pullRequests,
                testingActionSessions: testingData.actions
            )
        case .media: MediaPlaybackPage(model: mediaPlaybackModel, testingPlayback: testingData.media)
        case .clock: ClockPage(model: clockModel, testingStatus: testingData.clock)
        case .downloads: DownloadsPage(model: downloadModel, testingDownloads: testingData.downloads)
        case .aiAgent:
            AIAgentPage(
                model: aiAgentModel,
                permissions: computerUsePermissions,
                isActive: isExpanded && selectedPage == .aiAgent
            )
        }
    }

    private func displayedPages(at date: Date) -> [NotchPage] {
        let testingData = testingPreviewData(at: date)
        return DynamicPageActivity(
            calendar: testingData.schedule != nil || calendarHasActivity(at: date),
            agents: !(testingData.sessions ?? []).isEmpty || agentsHaveActivity,
            agentUsage: usageLimitNeedsAttention,
            github: testingData.hasGitHubActivity || gitHubHasActivity,
            media: testingData.media != nil || mediaPlaybackModel.isPageActive(at: date),
            clock: testingData.clock != nil || clockModel.status(at: date, includePaused: true) != nil,
            downloads: !(testingData.downloads ?? []).isEmpty || !downloadModel.activeDownloads.isEmpty,
            aiAgent: preferences.aiAgentEnabled
        ).visiblePages(
            from: preferences.orderedVisiblePages,
            isEnabled: preferences.dynamicPagesEnabled
        )
    }

    private func calendarHasActivity(at date: Date) -> Bool {
        guard case let .loaded(schedule) = calendarModel.state else { return false }
        return !schedule.currentAndUpcoming(on: date, relativeTo: date).isEmpty
    }

    private func testingPreviewData(at date: Date) -> TestingPreviewData {
        TestingPreviewData.make(preferences: preferences, at: date)
    }

    private var agentsHaveActivity: Bool {
        guard case let .loaded(sessions) = codingAgentModel.state else { return false }
        return sessions.contains { $0.status == .running }
    }

    private var usageLimitNeedsAttention: Bool {
        guard case let .loaded(availability) = codingAgentModel.usageState else { return false }
        return SummaryHighlight.depletedUsageLimit(in: availability) != nil
    }

    private var gitHubHasActivity: Bool {
        let hasOpenPullRequests = if case let .loaded(pullRequests) = gitHubModel.state {
            !pullRequests.isEmpty
        } else {
            false
        }
        return hasOpenPullRequests || gitHubModel.actionSessions.contains { $0.status == .running }
    }

    private func selectedPageIndex(in pages: [NotchPage]) -> Int {
        pages.firstIndex(of: selectedPage) ?? 0
    }

    private func nextPage(in pages: [NotchPage]) -> NotchPage {
        wrappingPage(in: pages, from: selectedPage, offset: 1) ?? selectedPage
    }

    private func previousPage(in pages: [NotchPage]) -> NotchPage {
        wrappingPage(in: pages, from: selectedPage, offset: -1) ?? selectedPage
    }
}

enum SystemActivityLayout {
    static let sideWidth: CGFloat = 38

    static func externalCenterWidth(for collapsedWidth: CGFloat) -> CGFloat {
        max(0, collapsedWidth - 2 * sideWidth)
    }
}

private struct NotchBackgroundShape: Shape {
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(size.width, size.height),
                AnimatablePair(topRadius, bottomRadius)
            )
        }
        set {
            size = CGSize(width: newValue.first.first, height: newValue.first.second)
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shapeRect = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.minY,
            width: size.width,
            height: size.height
        )
        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: topRadius,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: topRadius
            ),
            style: .continuous
        )
        .path(in: shapeRect)
    }
}

struct NotchHoverState {
    private(set) var canOpen = true
    private(set) var isHovering = false
    private var isClosing = false

    mutating func update(isHovering: Bool) {
        self.isHovering = isHovering
        if !isClosing, !isHovering { canOpen = true }
    }

    mutating func notchClosed() {
        guard isHovering else { return }
        canOpen = false
        isClosing = true
    }

    mutating func finishClosing() {
        isClosing = false
        if !isHovering { canOpen = true }
    }
}

enum NotchHoverSurface {
    case collapsed
    case expanded
}

func shouldHandleHover(from surface: NotchHoverSurface, isExpanded: Bool) -> Bool {
    switch surface {
    case .collapsed: !isExpanded
    case .expanded: isExpanded
    }
}

func wrappingPage(in pages: [NotchPage], from selectedPage: NotchPage, offset: Int) -> NotchPage? {
    guard let selectedIndex = pages.firstIndex(of: selectedPage) else { return nil }
    let index = (selectedIndex + offset) % pages.count
    return pages[index >= 0 ? index : index + pages.count]
}

func shouldShowPageIndicator(for pages: [NotchPage]) -> Bool {
    pages.count > 1
}
