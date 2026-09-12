import PulseNotchCore
import SwiftUI

struct NotchPreview: View {
    private enum Page: Int, CaseIterable {
        case calendar
        case agents
    }

    private let calendarReminderLeadTime: TimeInterval = 10 * 60

    @ObservedObject var calendarModel: CalendarFeatureModel
    @ObservedObject var codingAgentModel: CodingAgentFeatureModel

    @State private var isExpanded = false
    @State private var selectedPage = Page.calendar
    @State private var pageDragOffset: CGFloat = 0
    @State private var selectedDate = Date()
    @State private var showsAllEvents = false
    @State private var showsAgentSetup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                notch(at: context.date)
            }

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

                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
        .onChange(of: codingAgentModel.state) { _, _ in
            if isExpanded {
                codingAgentModel.acknowledgeCompletedSessions()
            }
        }
        .task {
            while !Task.isCancelled {
                await codingAgentModel.refresh()

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
        .task(id: isExpanded && selectedPage == .agents) {
            guard isExpanded, selectedPage == .agents else {
                return
            }

            while !Task.isCancelled {
                await codingAgentModel.refreshUsage()

                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchOpen)) { _ in
            toggleNotch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowCalendar)) { _ in
            openNotch()
            selectPage(.calendar)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseNotchShowAgents)) { _ in
            openNotch()
            selectPage(.agents)
        }
    }

    private func notch(at date: Date) -> some View {
        Group {
            if isExpanded {
                expandedContent(at: date)
            } else {
                collapsedIndicators(at: date)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(
            width: isExpanded ? 500 : 190,
            height: isExpanded ? 250 : 42,
            alignment: .top
        )
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.25),
            value: isExpanded
        )
        .onChange(of: isExpanded) { _, isOpen in
            if isOpen {
                NotchHapticFeedback.performOpen()
            }
        }
        .onHover {
            isExpanded = $0
            if $0 {
                codingAgentModel.acknowledgeCompletedSessions()
            } else {
                showsAllEvents = false
            }
        }
        .onTapGesture {
            openNotch()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pulse Notch")
    }

    private func collapsedIndicators(at date: Date) -> some View {
        HStack(spacing: 8) {
            ForEach(collapsedNotchIndicators(at: date)) { indicator in
                NotchIndicatorView(
                    indicator: indicator,
                    reduceMotion: reduceMotion
                )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func expandedContent(at date: Date) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                expandedCalendarContent(at: date)
                    .frame(width: geometry.size.width)
                    .accessibilityHidden(selectedPage != .calendar)

                expandedAgentContent(at: date)
                    .frame(width: geometry.size.width)
                    .accessibilityHidden(selectedPage != .agents)
            }
            .offset(
                x: -CGFloat(selectedPage.rawValue) * geometry.size.width
                    + pageDragOffset
            )
        }
        .clipped()
        .overlay(alignment: .topTrailing) {
            pageIndicator()
                .padding(.top, 5)
        }
        .contentShape(Rectangle())
        .background {
            TrackpadSwipeDetector { direction in
                selectPage(direction == .left ? .agents : .calendar)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    pageDragOffset = value.translation.width
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        selectPage(selectedPage)
                        return
                    }
                    selectPage(
                        value.translation.width < 0 ? .agents : .calendar
                    )
                }
        )
    }

    private func pageIndicator() -> some View {
        HStack(spacing: 5) {
            ForEach(Page.allCases, id: \.self) { page in
                Circle()
                    .fill(page == selectedPage ? .white : .white.opacity(0.35))
                    .frame(
                        width: page == selectedPage ? 7 : 4,
                        height: page == selectedPage ? 7 : 4
                    )
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page indicator")
        .accessibilityValue(
            selectedPage == .calendar ? "Calendar page" : "Agents page"
        )
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selectedPage)
    }

    private func openNotch() {
        guard !isExpanded else {
            return
        }
        isExpanded = true
        codingAgentModel.acknowledgeCompletedSessions()
    }

    private func toggleNotch() {
        if isExpanded {
            isExpanded = false
            showsAllEvents = false
        } else {
            openNotch()
        }
    }

    private func selectPage(_ page: Page) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            selectedPage = page
            pageDragOffset = 0
        }
    }

    private func collapsedNotchIndicators(at date: Date) -> [NotchIndicator] {
        var indicators: [NotchIndicator] = []

        if case let .loaded(schedule) = calendarModel.state,
           let event = schedule.next(after: date),
           event.startsSoon(
               relativeTo: date,
               threshold: calendarReminderLeadTime
           ) {
            indicators.append(
                NotchIndicator(
                    id: "calendar-\(event.id)",
                    content: .upcomingCalendarEvent,
                    accessibilityLabel: "Calendar event starting within ten minutes"
                )
            )
        }

        if case .loaded = codingAgentModel.state {
            indicators.append(contentsOf: codingAgentModel.notificationSessions.prefix(4).map { session in
                let content: NotchIndicator.Content
                let statusDescription: String
                switch session.status {
                case .running:
                    content = .runningAgent(session.kind)
                    statusDescription = "running"
                case .completed:
                    content = .completedAgent(session.kind)
                    statusDescription = "completed"
                }

                return NotchIndicator(
                    id: session.id,
                    content: content,
                    accessibilityLabel: "\(session.kind.displayName) agent \(statusDescription)"
                )
            })
        }

        return Array(indicators.prefix(5))
    }

    @ViewBuilder
    private func expandedAgentContent(at date: Date) -> some View {
        switch codingAgentModel.state {
        case .loading:
            agentPlaceholder {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Detecting coding agents")
            }
        case let .loaded(sessions):
            agentContent(sessions, at: date)
        case .unavailable:
            agentPlaceholder {
                emptyState(
                    title: "Agent detection is unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    private func agentContent(
        _ sessions: [CodingAgentSession],
        at date: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coding agents")
                        .font(.headline)

                    Text(agentSummary(sessions))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if sessions.isEmpty {
                        emptyState(
                            title: "No coding agents detected",
                            systemImage: "checkmark.circle"
                        )
                    } else {
                        ForEach(sessions) { session in
                            agentRow(session, at: date)
                        }
                    }

                    usageSection(at: date)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func agentRow(
        _ session: CodingAgentSession,
        at date: Date
    ) -> some View {
        let isRunning = session.status == .running

        return HStack(spacing: 12) {
            AgentMark(kind: session.kind, size: 19)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Label(
                        workspaceName(for: session) ?? session.kind.displayName,
                        systemImage: workspaceName(for: session) == nil
                            ? "cpu"
                            : "folder"
                    )

                    if let branch = session.gitBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }

                    Label(
                        sessionDuration(session, relativeTo: date),
                        systemImage: "clock"
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            NotchIndicatorView(
                indicator: NotchIndicator(
                    id: session.id,
                    content: isRunning
                        ? .runningAgent(session.kind)
                        : .completedAgent(session.kind),
                    accessibilityLabel: isRunning ? "Running" : "Completed"
                ),
                reduceMotion: reduceMotion
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func usageSection(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Usage limits", systemImage: "chart.pie.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            switch codingAgentModel.usageState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading coding agent usage limits")
            case let .loaded(usages):
                if usages.isEmpty {
                    Text("No compatible usage data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(usages) { usage in
                        usageRow(usage, at: date)
                    }
                }

                agentSetupOptions(
                    excluding: Set(usages.map(\.kind))
                )
            case .unavailable:
                Label("Usage limits are unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func agentSetupOptions(
        excluding installedKinds: Set<CodingAgentKind>
    ) -> some View {
        let unavailableKinds = CodingAgentKind.allCases.filter {
            !installedKinds.contains($0)
        }

        if !unavailableKinds.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                        showsAgentSetup.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showsAgentSetup ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.bold))

                        Text("Set up more agents")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set up more coding agents")
                .accessibilityValue(showsAgentSetup ? "Expanded" : "Collapsed")

                if showsAgentSetup {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(unavailableKinds, id: \.self) { kind in
                        HStack(alignment: .top, spacing: 7) {
                            AgentMark(kind: kind, size: 12)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.displayName)
                                    .font(.caption.weight(.semibold))
                                Text(setupInstruction(for: kind))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 2)
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func setupInstruction(for kind: CodingAgentKind) -> String {
        switch kind {
        case .codex:
            "Install the Codex app or CLI."
        case .claude:
            "Install Claude Code CLI, then connect /statusline."
        case .cursor:
            "Install cursor-agent, then run cursor-agent login."
        case .antigravity:
            "Install the agy CLI."
        case .opencode:
            "Install opencode, then configure a provider with /connect."
        }
    }

    private func usageRow(
        _ usage: CodingAgentUsage,
        at date: Date
    ) -> some View {
        HStack(spacing: 12) {
            AgentMark(kind: usage.kind, size: 15)
                .frame(width: 24)

            Text(usage.kind.displayName)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 8)

            if usage.windows.isEmpty {
                Text(unavailableUsageDescription(usage.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else {
                HStack(spacing: 16) {
                    ForEach(usage.windows) { window in
                        usageGauge(window, color: agentColor(usage.kind), at: date)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private func usageGauge(
        _ window: CodingAgentUsage.Window,
        color: Color,
        at date: Date
    ) -> some View {
        let remaining = Int(window.remainingPercent.rounded())
        let reset = window.resetsAt.map {
            relativeDescription($0, relativeTo: date)
        }

        return HStack(spacing: 7) {
            TinyUsageRing(value: window.remainingPercent, color: color)

            Text("\(usageWindowName(window)) \(remaining)%")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .help(reset.map { "Resets \($0)" } ?? "Reset time unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(usageWindowName(window)) limit, \(remaining) percent remaining"
        )
        .accessibilityValue(reset.map { "Resets \($0)" } ?? "Reset time unavailable")
    }

    private func unavailableUsageDescription(_ kind: CodingAgentKind) -> String {
        switch kind {
        case .codex: "Usage unavailable"
        case .claude: "Run /statusline to connect"
        case .cursor: "View monthly usage in Cursor"
        case .antigravity: "Usage unavailable"
        case .opencode: "Usage depends on its configured provider"
        }
    }

    private func usageWindowName(_ window: CodingAgentUsage.Window) -> String {
        if let label = window.label {
            return label
        }
        return switch window.durationMinutes {
        case 300: "5 h"
        case 10_080: "Week"
        case 43_200, 43_800, 44_640: "Month"
        case let minutes?: "\(max(minutes / 60, 1)) h"
        case nil: "Limit"
        }
    }

    private func agentSummary(_ sessions: [CodingAgentSession]) -> String {
        let runningCount = sessions.count { $0.status == .running }
        if runningCount == 0 {
            return sessions.isEmpty ? "Watching this Mac" : "Recently completed"
        }
        return "\(runningCount) running"
    }

    private func workspaceName(for session: CodingAgentSession) -> String? {
        guard let directory = session.workingDirectory else {
            return nil
        }
        let name = URL(fileURLWithPath: directory).lastPathComponent
        return name.isEmpty ? directory : name
    }

    private func sessionDuration(
        _ session: CodingAgentSession,
        relativeTo date: Date
    ) -> String {
        let end: Date
        switch session.status {
        case .running:
            end = date
        case let .completed(completedAt):
            end = completedAt
        }

        let seconds = max(Int(end.timeIntervalSince(session.startedAt)), 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return minutes > 0 ? "\(minutes)m" : "now"
    }

    private func relativeDescription(
        _ target: Date,
        relativeTo reference: Date
    ) -> String {
        RelativeDateTimeFormatter().localizedString(
            for: target,
            relativeTo: reference
        )
    }

    private func agentColor(_ kind: CodingAgentKind) -> Color {
        switch kind {
        case .codex: .cyan
        case .claude: .orange
        case .cursor: .purple
        case .antigravity: .indigo
        case .opencode: .mint
        }
    }

    private func agentPlaceholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Coding agents")
                    .font(.headline)

                Spacer()
            }

            Divider()

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func expandedCalendarContent(at date: Date) -> some View {
        switch calendarModel.state {
        case .loading:
            placeholder {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading next calendar event")
            }
        case let .loaded(schedule):
            calendarContent(schedule, at: date)
        case .accessDenied:
            placeholder {
                emptyState(
                    title: "Calendar access is off",
                    systemImage: "calendar.badge.exclamationmark"
                )
            }
        case .unavailable:
            placeholder {
                emptyState(
                    title: "Calendar is unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    private func calendarContent(
        _ schedule: CalendarEventSchedule,
        at date: Date
    ) -> some View {
        let events = schedule.events(on: selectedDate)
        let initialEvents = Array(
            schedule.currentAndUpcoming(
                on: selectedDate,
                relativeTo: date
            ).prefix(2)
        )
        let hiddenEventCount = events.count - initialEvents.count

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDate, format: .dateTime.month(.abbreviated))
                        .font(.title2.weight(.semibold))

                    Text(selectedDate, format: .dateTime.year())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(weekDates(containing: selectedDate), id: \.self) { day in
                        let isSelected = Calendar.autoupdatingCurrent.isDate(
                            day,
                            inSameDayAs: selectedDate
                        )

                        Button {
                            selectedDate = day
                            showsAllEvents = false
                        } label: {
                            VStack(spacing: 5) {
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(day, format: .dateTime.day())
                                    .font(.callout.weight(isSelected ? .bold : .regular))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        isSelected ? Color.accentColor : .clear,
                                        in: Circle()
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, 34)
            }

            if events.isEmpty {
                emptyState(
                    title: "No events on this day",
                    systemImage: "calendar.badge.checkmark"
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    let visibleEvents = showsAllEvents ? events : initialEvents

                    if visibleEvents.isEmpty {
                        emptyState(
                            title: "No more events today",
                            systemImage: "calendar.badge.checkmark"
                        )
                    } else if showsAllEvents {
                        ScrollView(.vertical, showsIndicators: false) {
                            eventRows(visibleEvents, at: date)
                        }
                    } else {
                        eventRows(visibleEvents, at: date)
                    }

                    if hiddenEventCount > 0 {
                        Button {
                            withAnimation(
                                reduceMotion ? nil : .snappy(duration: 0.2)
                            ) {
                                showsAllEvents.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(
                                    showsAllEvents
                                        ? "Show upcoming"
                                        : "+\(hiddenEventCount) "
                                            + (hiddenEventCount == 1 ? "event" : "events")
                                )

                                Image(
                                    systemName: showsAllEvents
                                        ? "chevron.up"
                                        : "chevron.down"
                                )
                                .font(.caption2.weight(.semibold))
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            showsAllEvents
                                ? "Shows only upcoming events"
                                : "Shows all events for this day"
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private func eventRows(
        _ events: [CalendarEvent],
        at date: Date
    ) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(events) { event in
                eventRow(event, at: date)
            }
        }
    }

    private func eventRow(
        _ event: CalendarEvent,
        at date: Date
    ) -> some View {
        let eventColor = Color(
            red: event.calendarColor.red,
            green: event.calendarColor.green,
            blue: event.calendarColor.blue,
            opacity: event.calendarColor.opacity
        )

        return HStack(spacing: 10) {
            Capsule()
                .fill(eventColor)
                .frame(width: 3, height: 36)
                .accessibilityHidden(true)

            Group {
                if event.isAllDay {
                    Text("All-day")
                } else {
                    Text(event.startsAt, format: .dateTime.hour().minute())
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(
                event.startsSoon(relativeTo: date)
                    ? Color.orange
                    : Color.white.opacity(0.55)
            )
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(event.calendarName)
                        .foregroundStyle(eventColor)

                    if let location = event.location {
                        Label(location, systemImage: "mappin")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption2.weight(.medium))

                if let notes = event.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if !event.isAllDay, event.isInProgress(relativeTo: date) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(eventColor)
                    .symbolEffect(
                        .variableColor.iterative.reversing,
                        options: .repeating,
                        isActive: !reduceMotion
                    )
                    .accessibilityLabel("Event in progress")
            }

            if let meetingURL = event.meetingURL {
                Button {
                    openURL(meetingURL)
                } label: {
                    Image(systemName: "video.fill")
                        .frame(width: 26, height: 26)
                        .foregroundStyle(eventColor)
                        .background(eventColor.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(event.title)")
                .accessibilityHint(
                    "Opens the meeting in your default browser"
                )
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekDates(containing date: Date) -> [Date] {
        let calendar = Calendar.autoupdatingCurrent
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return [date]
        }

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: week.start)
        }
    }

    private func placeholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Calendar")
                    .font(.headline)

                Spacer()
            }

            Divider()

            content()
        }
    }

    private func emptyState(
        title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TinyUsageRing: View {
    let value: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: value / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
