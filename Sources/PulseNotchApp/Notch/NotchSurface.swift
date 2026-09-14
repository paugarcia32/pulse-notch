import PulseNotchCore
import SwiftUI

struct NotchSurface: View {
    @ObservedObject var calendarModel: CalendarFeatureModel
    @ObservedObject var codingAgentModel: CodingAgentFeatureModel
    @ObservedObject var gitHubModel: GitHubFeatureModel
    @ObservedObject var preferences: NotchPreferences
    @ObservedObject var transientActivityModel: TransientNotchActivityModel
    @StateObject private var systemControlMonitor = SystemControlMonitor()
    @State private var isExpanded = false
    @State private var selectedPage = NotchPage.calendar
    @State private var pageDragOffset: CGFloat = 0
    @State private var isHoveringPageIndicator = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 15)) { notch(at: $0.date) }
            Text("Hover over the notch to preview its expanded state.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 620, height: 360)
        .background(.regularMaterial)
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
        .task { systemControlMonitor.start() }
        .onDisappear { systemControlMonitor.stop() }
        .onReceive(systemControlMonitor.$activity.compactMap { $0 }) { activity in
            guard !isExpanded else { return }
            transientActivityModel.show(activity)
        }
    }

    private func notch(at date: Date) -> some View {
        Group {
            if isExpanded { expandedContent(at: date) } else { collapsedIndicators(at: date) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: isExpanded ? 500 : transientActivityModel.activity == nil ? 190 : 330, height: isExpanded ? 250 : 42, alignment: .top)
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isExpanded)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: transientActivityModel.activity)
        .onChange(of: isExpanded) { _, isOpen in
            if isOpen {
                transientActivityModel.dismiss()
                NotchHapticFeedback.performOpen()
            }
        }
        .onHover { hovering in
            isExpanded = hovering
            if hovering {
                codingAgentModel.acknowledgeCompletedSessions()
                gitHubModel.acknowledgeCompletedActions()
            }
        }
        .onTapGesture { openNotch() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pulse Notch")
    }

    @ViewBuilder
    private func collapsedIndicators(at date: Date) -> some View {
        if let activity = transientActivityModel.activity {
            TransientNotchActivityView(activity: activity)
        } else {
            let currentIndicators = indicators(at: date)
            if case let .upcomingCalendarEvent(minutesUntilStart) = currentIndicators.first?.content {
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
        .overlay(alignment: .topTrailing) { pageIndicator().offset(y: -3) }
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

    private func indicators(at date: Date) -> [NotchIndicator] {
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
        )
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
