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
    @State private var selectedPage = NotchPage.calendar
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
        .onChange(of: preferences.orderedVisiblePages) { _, pages in handleVisiblePagesChange(pages) }
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
        .task {
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
        .task {
            while !Task.isCancelled {
                await gitHubModel.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task {
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
        .task {
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
            notch(at: context.date)
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

    private func notch(at date: Date) -> some View {
        Group {
            if isExpanded { expandedContent(at: date) } else { collapsedIndicators(at: date) }
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
                    color: currentIndicators[0].color,
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
                        .foregroundStyle(currentIndicators[0].color)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(currentIndicators[0].accessibilityLabel)
            } else {
                HStack(spacing: 8) {
                    ForEach(currentIndicators) {
                        NotchIndicatorView(indicator: $0, reduceMotion: reduceMotion)
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
        let mediaIndicator = indicators.first { indicator in
            if case .mediaPlayback = indicator.content { return true }
            return false
        }
        let calendarIndicator = indicators.first { indicator in
            if case .upcomingCalendarEvent = indicator.content { return true }
            return false
        }
        let primaryIndicator = mediaIndicator ?? calendarIndicator
        let otherIndicators = indicators.filter {
            $0.id != primaryIndicator?.id && $0.id != calendarIndicator?.id
        }
        let indicatorCountPerSide = primaryIndicator == nil
            ? preferences.collapsedIndicatorMaximumPerSide
            : max(0, preferences.collapsedIndicatorMaximumPerSide - 1)
        let leftIndicators = Array(otherIndicators.prefix(indicatorCountPerSide))
        let rightIndicators = Array(otherIndicators.dropFirst(indicatorCountPerSide).prefix(indicatorCountPerSide))
        // A paired indicator occupies the same slot on both sides of the notch.
        let pairedContentWidth: CGFloat = mediaIndicator != nil && calendarIndicator != nil ? 50 : 0
        let leftWidth = collapsedSideWidth(
            itemCount: leftIndicators.count,
            additionalContentWidth: pairedContentWidth > 0 ? pairedContentWidth : mediaIndicator == nil
                ? (calendarIndicator == nil ? 0 : 16)
                : 22
        )
        let rightWidth = collapsedSideWidth(
            itemCount: rightIndicators.count,
            additionalContentWidth: pairedContentWidth > 0 ? pairedContentWidth : mediaIndicator == nil
                ? (calendarIndicator == nil ? 0 : 28)
                : 16
        )

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let mediaIndicator, case let .mediaPlayback(playback) = mediaIndicator.content {
                    MediaArtworkView(data: playback.artworkData, size: 22)
                        .accessibilityLabel(mediaIndicator.accessibilityLabel)
                    if let calendarIndicator {
                        CalendarCountdownIcon(color: calendarIndicator.color)
                        .accessibilityLabel(calendarIndicator.accessibilityLabel)
                    }
                    ForEach(leftIndicators) { NotchIndicatorView(indicator: $0, reduceMotion: reduceMotion) }
                } else if let calendarIndicator {
                    ForEach(leftIndicators) { NotchIndicatorView(indicator: $0, reduceMotion: reduceMotion) }
                    CalendarCountdownIcon(color: calendarIndicator.color)
                        .accessibilityLabel(calendarIndicator.accessibilityLabel)
                } else {
                    ForEach(leftIndicators) { NotchIndicatorView(indicator: $0, reduceMotion: reduceMotion) }
                }
            }
            .padding(.leading, NotchSurfaceSize.collapsedIndicatorOuterPadding)
            .padding(.trailing, NotchSurfaceSize.physicalNotchContentSpacing)
            .frame(width: leftWidth, height: notchSize.height, alignment: .trailing)

            Color.clear
                .frame(width: notchSize.width, height: notchSize.height)
                .accessibilityHidden(true)

            HStack(spacing: 8) {
                if let calendarIndicator, case let .upcomingCalendarEvent(minutesUntilStart) = calendarIndicator.content {
                    CalendarCountdownValue(minutesUntilStart: minutesUntilStart, reduceMotion: reduceMotion)
                        .foregroundStyle(calendarIndicator.color)
                        .accessibilityHidden(true)
                }
                if let mediaIndicator, case let .mediaPlayback(playback) = mediaIndicator.content {
                    MediaEqualizer(isPlaying: playback.isPlaying, reduceMotion: reduceMotion)
                        .foregroundStyle(mediaIndicator.color)
                        .accessibilityHidden(true)
                }
                ForEach(rightIndicators) { NotchIndicatorView(indicator: $0, reduceMotion: reduceMotion) }
            }
            .padding(.leading, NotchSurfaceSize.physicalNotchContentSpacing)
            .padding(.trailing, NotchSurfaceSize.collapsedIndicatorOuterPadding)
            .frame(width: rightWidth, height: notchSize.height, alignment: .leading)
        }
        .background { AttachedNotchShape(bottomCornerRadius: 8).fill(.black) }
        .offset(x: (rightWidth - leftWidth) / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func collapsedSideWidth(itemCount: Int, additionalContentWidth: CGFloat = 0) -> CGFloat {
        guard itemCount > 0 || additionalContentWidth > 0 else { return 0 }
        let contentWidth = CGFloat(itemCount) * 16
            + additionalContentWidth
            + CGFloat(max(itemCount - 1 + (additionalContentWidth > 0 && itemCount > 0 ? 1 : 0), 0)) * 8
        return contentWidth
            + NotchSurfaceSize.collapsedIndicatorOuterPadding
            + NotchSurfaceSize.physicalNotchContentSpacing
    }

    private func expandedContent(at date: Date) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(preferences.orderedVisiblePages) { page in
                    pageContent(page, at: date)
                        .frame(width: geometry.size.width)
                        .accessibilityHidden(selectedPage != page)
                }
            }
            .offset(x: -CGFloat(selectedPageIndex) * geometry.size.width + pageDragOffset)
        }
        .clipped()
        .padding(.top, physicalNotchSize?.height ?? 0)
        .overlay(alignment: .topTrailing) {
            pageIndicator().offset(y: (physicalNotchSize?.height ?? 0) - 3)
        }
        .contentShape(Rectangle())
        .background {
            TrackpadSwipeDetector { selectPage($0 == .left ? nextPage : previousPage) }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged {
                    guard abs($0.translation.width) > abs($0.translation.height) else { return }
                    pageDragOffset = $0.translation.width
                }
                .onEnded {
                    guard abs($0.translation.width) > abs($0.translation.height) else {
                        selectPage(selectedPage)
                        return
                    }
                    selectPage($0.translation.width < 0 ? nextPage : previousPage)
                }
        )
    }

    private func pageIndicator() -> some View {
        HStack(spacing: -3) {
            ForEach(preferences.orderedVisiblePages) { page in
                Button { selectPage(page) } label: {
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
            if !previews.isEmpty { return previews }
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
        return CollapsedNotchIndicators.make(
            schedule: schedule,
            sessions: sessions,
            actionSessions: gitHubModel.notificationActionSessions,
            downloads: preferences.showDownloads ? downloadModel.activeDownloads : [],
            mediaPlayback: mediaPlaybackModel.playback,
            at: date,
            calendarReminderLeadTime: preferences.calendarReminderLeadTime
        ).filter { preferences.isCollapsedIndicatorCategoryVisible($0.category) }
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

    private func selectPage(_ page: NotchPage) {
        guard preferences.orderedVisiblePages.contains(page) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            selectedPage = page
            pageDragOffset = 0
        }
    }

    @ViewBuilder
    private func pageContent(_ page: NotchPage, at date: Date) -> some View {
        switch page {
        case .calendar: CalendarPage(model: calendarModel, date: date)
        case .agents: CodingAgentsPage(model: codingAgentModel, date: date)
        case .github: GitHubPage(model: gitHubModel, date: date)
        case .media: MediaPlaybackPage(model: mediaPlaybackModel)
        }
    }

    private var selectedPageIndex: Int { preferences.orderedVisiblePages.firstIndex(of: selectedPage) ?? 0 }
    private var nextPage: NotchPage { wrappingPage(in: preferences.orderedVisiblePages, from: selectedPage, offset: 1) ?? selectedPage }
    private var previousPage: NotchPage { wrappingPage(in: preferences.orderedVisiblePages, from: selectedPage, offset: -1) ?? selectedPage }
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
