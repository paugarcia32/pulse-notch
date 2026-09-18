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
    let bluetoothHeadphonesModel: BluetoothHeadphonesFeatureModel
    @ObservedObject var systemActivityModel: SystemActivityFeatureModel
    @ObservedObject var preferences: NotchPreferences
    let isExternalDisplay: Bool
    let physicalNotchSize: CGSize?
    let onExpansionChanged: (Bool) -> Void
    @State private var isExpanded = false
    @State private var selectedPage = NotchPage.summary
    @State private var pageDragOffset: CGFloat = 0
    @State private var isHoveringPageIndicator = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var systemActivityTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        activitySurface
    }

    private var navigationSurface: some View {
        refreshingSurface
        .onChange(of: codingAgentModel.state) { _, _ in
            acknowledgeCompletedActivity()
        }
        .onChange(of: gitHubModel.actionSessions) { _, _ in
            acknowledgeCompletedActivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchOpen)) { _ in toggleNotch() }
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
        .onChange(of: preferences.orderedVisiblePages) { _, _ in
            handleVisiblePagesChange(displayedPages(at: .now))
        }
        .onChange(of: preferences.dynamicPagesEnabled) { _, _ in
            handleVisiblePagesChange(displayedPages(at: .now))
        }
        .onChange(of: isExpanded) { _, expanded in onExpansionChanged(expanded) }
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
            volumeModel.stopMonitoring()
            brightnessModel.stopMonitoring()
            downloadModel.stopMonitoring()
        }
    }

    private var refreshingSurface: some View {
        surface
        .task(id: preferences.isVisible(.calendar) || preferences.isVisible(.summary)) {
            guard preferences.isVisible(.calendar) || preferences.isVisible(.summary) else { return }
            while !Task.isCancelled {
                await calendarModel.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task {
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
            await downloadModel.startMonitoring(directory: preferences.downloadsDirectoryURL)
            // ponytail: scan once per second. Browser downloads have no public
            // system-wide activity API; use a file-system event source only if
            // polling proves measurably too expensive.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await downloadModel.refresh()
            }
        }
        .task { await volumeModel.startMonitoring() }
        .task {
            await brightnessModel.startMonitoring()
            // ponytail: CoreBrightness has no public observation API. This
            // keeps unsupported systems responsive while notifications cover
            // the usual immediate path.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await brightnessModel.refresh()
            }
        }
        .task(id: preferences.isVisible(.github) || preferences.isVisible(.summary)) {
            guard preferences.isVisible(.github) || preferences.isVisible(.summary) else { return }
            while !Task.isCancelled {
                await gitHubModel.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: preferences.isVisible(.agents) || preferences.isVisible(.summary)) {
            guard preferences.isVisible(.agents) || preferences.isVisible(.summary) else { return }
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
        .task(id: preferences.isVisible(.media) || preferences.isVisible(.summary)) {
            guard preferences.isVisible(.media) || preferences.isVisible(.summary) else { return }
            while !Task.isCancelled {
                await mediaPlaybackModel.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: isExpanded && selectedPage == .agents) {
            guard isExpanded, selectedPage == .agents else { return }
            while !Task.isCancelled {
                await codingAgentModel.refreshUsage()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var surface: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let pages = displayedPages(at: context.date)
            notch(at: context.date, pages: pages)
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
        Group {
            if isExpanded { expandedContent(at: date, pages: pages) } else { collapsedIndicators(at: date) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, isExpanded ? 18 : 12)
        .padding(.vertical, isExpanded ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { notchBackground }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isExpanded)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: systemActivityModel.activity)
        .onChange(of: isExpanded) { _, isOpen in
            if isOpen { NotchHapticFeedback.performOpen() }
        }
        .onHover(perform: handleHover)
        .onTapGesture { openNotch() }
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
            } else if case let .upcomingCalendarEvent(minutesUntilStart) = currentIndicators.first?.content {
                CalendarCountdownIndicator(
                    minutesUntilStart: minutesUntilStart,
                    color: collapsedIndicatorColor(for: currentIndicators[0]),
                    reduceMotion: reduceMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(currentIndicators[0].accessibilityLabel)
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
            .background { AttachedNotchShape(bottomCornerRadius: 8).fill(.black) }
            .frame(width: physicalNotchSize.width + 2 * systemActivitySideWidth, height: physicalNotchSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.accessibilityLabel)
        } else {
            HStack(spacing: 8) {
                Image(systemName: activity.symbolName)
                activityLevel(activity)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(activity.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.accessibilityLabel)
        }
    }

    private var systemActivitySideWidth: CGFloat { 38 }

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
        .background { AttachedNotchShape(bottomCornerRadius: 8).fill(.black) }
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
            case let (.mediaPlayback(playback), .left):
                MediaArtworkView(data: playback.artworkData, size: 22)
                    .accessibilityLabel(indicator.accessibilityLabel)
            case let (.mediaPlayback(playback), .right):
                MediaEqualizer(isPlaying: playback.isPlaying, reduceMotion: reduceMotion)
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

    private func collapsedIndicatorColor(for indicator: NotchIndicator) -> Color {
        collapsedIndicatorColorOverride(for: indicator) ?? indicator.color
    }

    private func collapsedIndicatorColorOverride(for indicator: NotchIndicator) -> Color? {
        guard indicator.supportsCustomColor else { return nil }
        return preferences.customCollapsedIndicatorColor(for: indicator.category)
    }

    private func expandedContent(at date: Date, pages: [NotchPage]) -> some View {
        Group {
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
                            pageContent(page, at: date)
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
        .padding(.top, physicalNotchSize?.height ?? 0)
        .overlay(alignment: .topTrailing) {
            pageIndicator(pages: pages).offset(y: (physicalNotchSize?.height ?? 0) - 3)
        }
        .contentShape(Rectangle())
        .background {
            TrackpadSwipeDetector {
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
                }
        )
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

    @ViewBuilder
    private var notchBackground: some View {
        if isExpanded {
            AttachedNotchShape(bottomCornerRadius: 18).fill(.black)
        } else if physicalNotchSize != nil {
            Color.clear
        } else if !isExternalDisplay || preferences.externalNotchStyle == .rectangle {
            AttachedNotchShape(bottomCornerRadius: 8).fill(.black)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius).fill(.black)
        }
    }

    private var cornerRadius: CGFloat {
        12
    }

    private func indicators(at date: Date) -> [NotchIndicator] {
        if preferences.testingFeaturesEnabled {
            let previews = CollapsedIndicatorPreview.allCases
                .flatMap { preview in
                    (0..<preferences.collapsedIndicatorPreviewCount(preview)).map {
                        preview.indicator(instance: $0)
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
            at: date,
            calendarReminderLeadTime: preferences.calendarReminderLeadTime
        ).filter { preferences.isCollapsedIndicatorCategoryVisible($0.category) }
        return CollapsedNotchIndicators.prioritize(
            indicators,
            using: preferences.collapsedIndicatorPriorityOrder
        )
    }

    private var downloadsMonitoringID: String {
        "\(preferences.showDownloads)-\(preferences.downloadsDirectoryPath)"
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
        codingAgentModel.acknowledgeCompletedSessions()
        gitHubModel.acknowledgeCompletedActions()
    }

    private func toggleNotch() {
        isExpanded ? (isExpanded = false) : openNotch()
    }

    private func closeNotch() {
        isExpanded = false
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        if hovering {
            guard !isExpanded else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                openNotch()
            }
        } else if isExpanded {
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
    private func pageContent(_ page: NotchPage, at date: Date) -> some View {
        switch page {
        case .summary:
            SummaryPage(
                calendarModel: calendarModel,
                codingAgentModel: codingAgentModel,
                gitHubModel: gitHubModel,
                mediaPlaybackModel: mediaPlaybackModel,
                priorities: preferences.summaryPriorityOrder,
                date: date,
                onSelectPage: { selectPage($0) }
            )
        case .calendar: CalendarPage(model: calendarModel, date: date)
        case .agents: CodingAgentsPage(model: codingAgentModel, date: date)
        case .github: GitHubPage(model: gitHubModel, date: date)
        case .media: MediaPlaybackPage(model: mediaPlaybackModel)
        }
    }

    private func displayedPages(at date: Date) -> [NotchPage] {
        DynamicPageActivity(
            calendar: calendarHasActivity(at: date),
            agents: agentsHaveActivity,
            github: gitHubHasActivity,
            media: mediaPlaybackModel.isPageActive(at: date)
        ).visiblePages(
            from: preferences.orderedVisiblePages,
            isEnabled: preferences.dynamicPagesEnabled
        )
    }

    private func calendarHasActivity(at date: Date) -> Bool {
        guard case let .loaded(schedule) = calendarModel.state else { return false }
        return !schedule.currentAndUpcoming(on: date, relativeTo: date).isEmpty
    }

    private var agentsHaveActivity: Bool {
        guard case let .loaded(sessions) = codingAgentModel.state else { return false }
        return sessions.contains { $0.status == .running }
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

func wrappingPage(in pages: [NotchPage], from selectedPage: NotchPage, offset: Int) -> NotchPage? {
    guard let selectedIndex = pages.firstIndex(of: selectedPage) else { return nil }
    let index = (selectedIndex + offset) % pages.count
    return pages[index >= 0 ? index : index + pages.count]
}

private struct AttachedNotchShape: Shape {
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomCornerRadius, rect.width / 2, rect.height)
        return Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
