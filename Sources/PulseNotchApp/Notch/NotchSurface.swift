import PulseNotchCore
import SwiftUI

struct NotchSurface: View {
    private enum Page: Int, CaseIterable {
        case calendar
        case agents
        case github

        var accessibilityName: String {
            switch self {
            case .calendar: "Calendar"
            case .agents: "Agents"
            case .github: "GitHub"
            }
        }
    }

    private let calendarReminderLeadTime: TimeInterval = 10 * 60
    @ObservedObject var calendarModel: CalendarFeatureModel
    @ObservedObject var codingAgentModel: CodingAgentFeatureModel
    @ObservedObject var gitHubModel: GitHubFeatureModel
    @State private var isExpanded = false
    @State private var selectedPage = Page.calendar
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
    }

    private func notch(at date: Date) -> some View {
        Group {
            if isExpanded { expandedContent(at: date) } else { collapsedIndicators(at: date) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: isExpanded ? 500 : 190, height: isExpanded ? 250 : 42, alignment: .top)
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isExpanded)
        .onChange(of: isExpanded) { _, isOpen in
            if isOpen { NotchHapticFeedback.performOpen() }
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

    private func collapsedIndicators(at date: Date) -> some View {
        HStack(spacing: 8) {
            ForEach(indicators(at: date)) {
                NotchIndicatorView(indicator: $0, reduceMotion: reduceMotion)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func expandedContent(at date: Date) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                CalendarPage(model: calendarModel, date: date)
                    .frame(width: geometry.size.width)
                    .accessibilityHidden(selectedPage != .calendar)
                CodingAgentsPage(model: codingAgentModel, date: date)
                    .frame(width: geometry.size.width)
                    .accessibilityHidden(selectedPage != .agents)
                GitHubPage(model: gitHubModel, date: date)
                    .frame(width: geometry.size.width)
                    .accessibilityHidden(selectedPage != .github)
            }
            .offset(x: -CGFloat(selectedPage.rawValue) * geometry.size.width + pageDragOffset)
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
            ForEach(Page.allCases, id: \.self) { page in
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
                .accessibilityLabel("Show \(page.accessibilityName) page")
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
            calendarReminderLeadTime: calendarReminderLeadTime
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

    private func selectPage(_ page: Page) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            selectedPage = page
            pageDragOffset = 0
        }
    }

    private var nextPage: Page { Page(rawValue: min(selectedPage.rawValue + 1, Page.allCases.count - 1)) ?? selectedPage }
    private var previousPage: Page { Page(rawValue: max(selectedPage.rawValue - 1, 0)) ?? selectedPage }
}
