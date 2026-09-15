import PulseNotchCore
import SwiftUI

struct NotchSurface: View {
    @ObservedObject var calendarModel: CalendarFeatureModel
    @ObservedObject var codingAgentModel: CodingAgentFeatureModel
    @ObservedObject var gitHubModel: GitHubFeatureModel
    @ObservedObject var batteryModel: BatteryFeatureModel
    @ObservedObject var preferences: NotchPreferences
    let isExternalDisplay: Bool
    let physicalNotchSize: CGSize?
    let onExpansionChanged: (Bool) -> Void
    @State private var isExpanded = false
    @State private var selectedPage = NotchPage.calendar
    @State private var pageDragOffset: CGFloat = 0
    @State private var isHoveringPageIndicator = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var chargingActivityTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { notch(at: $0.date) }
        .task {
            while !Task.isCancelled {
                await calendarModel.refresh()
                try? await Task.sleep(for: .seconds(30))
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
        .task(id: isExpanded && selectedPage == .agents) {
            guard isExpanded, selectedPage == .agents else { return }
            while !Task.isCancelled {
                await codingAgentModel.refreshUsage()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: codingAgentModel.state) { _, _ in
            if isExpanded { codingAgentModel.acknowledgeCompletedSessions() }
        }
        .onChange(of: gitHubModel.actionSessions) { _, _ in
            if isExpanded { gitHubModel.acknowledgeCompletedActions() }
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
        .onChange(of: preferences.orderedVisiblePages) { _, pages in
            if !pages.contains(selectedPage), let firstPage = pages.first { selectedPage = firstPage }
        }
        .onChange(of: isExpanded) { _, expanded in onExpansionChanged(expanded) }
        .onChange(of: batteryModel.chargingActivity) { _, activity in
            guard preferences.showChargingActivity else {
                if let activity { batteryModel.dismissChargingActivity(id: activity.id) }
                return
            }
            scheduleChargingActivityDismissal(activity)
        }
        .onChange(of: preferences.testingChargingActivityTrigger) { _, trigger in
            guard trigger > 0, preferences.showChargingActivity else { return }
            batteryModel.showChargingActivity(chargeLevel: 72)
        }
        .onChange(of: preferences.showChargingActivity) { _, isShown in
            guard !isShown, let activity = batteryModel.chargingActivity else { return }
            batteryModel.dismissChargingActivity(id: activity.id)
        }
        .onDisappear { chargingActivityTask?.cancel() }
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: batteryModel.chargingActivity)
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
        if preferences.showChargingActivity, let activity = batteryModel.chargingActivity {
            chargingActivity(activity)
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
    private func chargingActivity(_ activity: BatteryFeatureModel.ChargingActivity) -> some View {
        if let physicalNotchSize {
            HStack(spacing: 0) {
                Image(systemName: "battery.100percent.bolt")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 40, height: physicalNotchSize.height, alignment: .trailing)
                    .padding(.trailing, 8)

                Color.clear
                    .frame(width: physicalNotchSize.width, height: physicalNotchSize.height)
                    .accessibilityHidden(true)

                Text("\(activity.chargeLevel)%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .frame(width: 46, height: physicalNotchSize.height, alignment: .trailing)
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
            }
            .background { AttachedNotchShape(bottomCornerRadius: 8).fill(.black) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery connected, \(activity.chargeLevel) percent")
        } else {
            HStack(spacing: 8) {
                Image(systemName: "battery.100percent.bolt")
                Text("\(activity.chargeLevel)%")
                    .monospacedDigit()
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery connected, \(activity.chargeLevel) percent")
        }
    }

    private func physicalNotchIndicators(_ indicators: [NotchIndicator], notchSize: CGSize) -> some View {
        let calendarIndicator = indicators.first { indicator in
            if case .upcomingCalendarEvent = indicator.content { return true }
            return false
        }
        let otherIndicators = indicators.filter { $0.id != calendarIndicator?.id }
        let indicatorCountPerSide = calendarIndicator == nil
            ? preferences.collapsedIndicatorMaximumPerSide
            : max(0, preferences.collapsedIndicatorMaximumPerSide - 1)
        let leftIndicators = Array(otherIndicators.prefix(indicatorCountPerSide))
        let rightIndicators = Array(otherIndicators.dropFirst(indicatorCountPerSide).prefix(indicatorCountPerSide))
        let leftWidth = collapsedSideWidth(itemCount: leftIndicators.count + (calendarIndicator == nil ? 0 : 1))
        let rightWidth = collapsedSideWidth(
            itemCount: rightIndicators.count,
            includesCalendarCountdown: calendarIndicator != nil
        )

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(leftIndicators) { NotchIndicatorView(indicator: $0, reduceMotion: reduceMotion) }
                if let calendarIndicator {
                    CalendarCountdownIcon(color: calendarIndicator.color)
                        .accessibilityLabel(calendarIndicator.accessibilityLabel)
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

    private func collapsedSideWidth(itemCount: Int, includesCalendarCountdown: Bool = false) -> CGFloat {
        guard itemCount > 0 || includesCalendarCountdown else { return 0 }
        let contentWidth = CGFloat(itemCount) * 16
            + (includesCalendarCountdown ? 28 : 0)
            + CGFloat(max(itemCount - 1 + (includesCalendarCountdown && itemCount > 0 ? 1 : 0), 0)) * 8
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
            at: date,
            calendarReminderLeadTime: preferences.calendarReminderLeadTime
        ).filter { preferences.isCollapsedIndicatorCategoryVisible($0.category) }
    }

    private func scheduleChargingActivityDismissal(_ activity: BatteryFeatureModel.ChargingActivity?) {
        chargingActivityTask?.cancel()
        guard let activity else { return }
        chargingActivityTask = Task { @MainActor in
            try? await Task.sleep(for: preferences.transientSystemActivityDuration)
            guard !Task.isCancelled else { return }
            batteryModel.dismissChargingActivity(id: activity.id)
        }
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
        }
    }

    private var selectedPageIndex: Int { preferences.orderedVisiblePages.firstIndex(of: selectedPage) ?? 0 }
    private var nextPage: NotchPage { preferences.orderedVisiblePages[min(selectedPageIndex + 1, preferences.orderedVisiblePages.count - 1)] }
    private var previousPage: NotchPage { preferences.orderedVisiblePages[max(selectedPageIndex - 1, 0)] }
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
