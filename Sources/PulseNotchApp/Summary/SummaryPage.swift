import PulseNotchCore
import SwiftUI

enum SummaryPriority: String, CaseIterable, Identifiable {
    case calendarEvent
    case githubAttention
    case media
    case openPullRequest
    case clock
    case usageLimits

    var id: String { "summary-priority-\(rawValue)" }

    var name: String {
        switch self {
        case .calendarEvent: "Next calendar event"
        case .githubAttention: "GitHub needing attention"
        case .media: "Now playing"
        case .openPullRequest: "Open pull request"
        case .clock: "Active timer or stopwatch"
        case .usageLimits: "Usage limits running low"
        }
    }

    var symbolName: String {
        switch self {
        case .calendarEvent: "calendar"
        case .githubAttention: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .media: "waveform"
        case .openPullRequest: "arrow.triangle.pull"
        case .clock: "timer"
        case .usageLimits: "gauge.with.dots.needle.67percent"
        }
    }
}

enum SummaryPreview: String, CaseIterable, Identifiable {
    case githubAttention
    case openPullRequest
    case usageLimits

    var id: String { rawValue }

    var name: String {
        switch self {
        case .githubAttention: "GitHub needing attention"
        case .openPullRequest: "Open pull request"
        case .usageLimits: "Usage limits running low"
        }
    }

    var maximumPreviewCount: Int { 1 }

    func testingPullRequest(at date: Date) -> GitHubPullRequest? {
        let reviewStatus: GitHubPullRequest.ReviewStatus
        let title: String
        let number: Int
        switch self {
        case .githubAttention:
            reviewStatus = .changesRequested
            title = "Address review feedback"
            number = 42
        case .openPullRequest:
            reviewStatus = .awaitingReview
            title = "Ready for review"
            number = 43
        case .usageLimits:
            return nil
        }

        guard let url = URL(string: "https://github.com/pulse-notch/pulse-notch/pull/\(number)") else { return nil }
        return GitHubPullRequest(
            id: "summary-preview-\(rawValue)",
            repository: "pulse-notch/pulse-notch",
            number: number,
            title: title,
            url: url,
            isDraft: false,
            reviewStatus: reviewStatus,
            commentCount: 2
        )
    }

    func testingUsage(at date: Date) -> [CodingAgentUsageAvailability]? {
        guard self == .usageLimits else { return nil }
        return [
            .available(
                CodingAgentUsage(
                    kind: .codex,
                    windows: [
                        .init(
                            durationMinutes: 300,
                            label: "5-hour",
                            usedPercent: 92,
                            resetsAt: date.addingTimeInterval(60 * 60)
                        )
                    ]
                )
            )
        ]
    }
}

enum SummaryHighlight: Equatable {
    case event(CalendarEvent)
    case pullRequest(GitHubPullRequest)
    case media(MediaPlaybackStatus)
    case clock(ClockStatus)
    case usage(kind: CodingAgentKind, window: CodingAgentUsage.Window)
    case allClear

    static func select(
        schedule: CalendarEventSchedule?,
        pullRequests: [GitHubPullRequest],
        agents: [CodingAgentSession],
        actions: [GitHubActionSession],
        media: MediaPlaybackStatus?,
        usage: [CodingAgentUsageAvailability] = [],
        clock: ClockStatus? = nil,
        priorities: [SummaryPriority],
        at date: Date
    ) -> SummaryHighlight {
        let mostDepletedLimit = depletedUsageLimit(in: usage)

        for priority in priorities {
            switch priority {
            case .calendarEvent:
                if let event = schedule?.currentAndUpcoming(on: date, relativeTo: date).first {
                    return .event(event)
                }
            case .githubAttention:
                if let pullRequest = pullRequests.first(where: { $0.needsAttention }) {
                    return .pullRequest(pullRequest)
                }
            case .media:
                if let media { return .media(media) }
            case .openPullRequest:
                if let pullRequest = pullRequests.first(where: { !$0.needsAttention }) {
                    return .pullRequest(pullRequest)
                }
            case .clock:
                if let clock { return .clock(clock) }
            case .usageLimits:
                if let (kind, window) = mostDepletedLimit {
                    return .usage(kind: kind, window: window)
                }
            }
        }
        return .allClear
    }

    static func depletedUsageLimit(
        in usage: [CodingAgentUsageAvailability]
    ) -> (kind: CodingAgentKind, window: CodingAgentUsage.Window)? {
        let mostDepletedLimit = usage.compactMap { availability -> CodingAgentUsage? in
            guard case let .available(usage) = availability else { return nil }
            return usage
        }
        .flatMap { usage in usage.windows.map { (usage.kind, $0) } }
        .max { $0.1.usedPercent < $1.1.usedPercent }
        guard let mostDepletedLimit, mostDepletedLimit.1.usedPercent >= 80 else { return nil }
        return mostDepletedLimit
    }
}

struct SummaryPage: View {
    @ObservedObject var calendarModel: CalendarFeatureModel
    @ObservedObject var codingAgentModel: CodingAgentFeatureModel
    @ObservedObject var gitHubModel: GitHubFeatureModel
    @ObservedObject var mediaPlaybackModel: MediaPlaybackFeatureModel
    @ObservedObject var clockModel: ClockFeatureModel
    let priorities: [SummaryPriority]
    let date: Date
    let availablePages: Set<NotchPage>
    let onSelectPage: (NotchPage) -> Void
    let testingSchedule: CalendarEventSchedule?
    let testingSessions: [CodingAgentSession]?
    let testingActions: [GitHubActionSession]?
    let testingPullRequests: [GitHubPullRequest]?
    let testingUsage: [CodingAgentUsageAvailability]?
    let testingMedia: MediaPlaybackStatus?
    let testingClock: ClockStatus?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        calendarModel: CalendarFeatureModel,
        codingAgentModel: CodingAgentFeatureModel,
        gitHubModel: GitHubFeatureModel,
        mediaPlaybackModel: MediaPlaybackFeatureModel,
        clockModel: ClockFeatureModel,
        priorities: [SummaryPriority],
        date: Date,
        availablePages: Set<NotchPage>,
        onSelectPage: @escaping (NotchPage) -> Void,
        testingSchedule: CalendarEventSchedule? = nil,
        testingSessions: [CodingAgentSession]? = nil,
        testingActions: [GitHubActionSession]? = nil,
        testingPullRequests: [GitHubPullRequest]? = nil,
        testingUsage: [CodingAgentUsageAvailability]? = nil,
        testingMedia: MediaPlaybackStatus? = nil,
        testingClock: ClockStatus? = nil
    ) {
        self.calendarModel = calendarModel
        self.codingAgentModel = codingAgentModel
        self.gitHubModel = gitHubModel
        self.mediaPlaybackModel = mediaPlaybackModel
        self.clockModel = clockModel
        self.priorities = priorities
        self.date = date
        self.availablePages = availablePages
        self.onSelectPage = onSelectPage
        self.testingSchedule = testingSchedule
        self.testingSessions = testingSessions
        self.testingActions = testingActions
        self.testingPullRequests = testingPullRequests
        self.testingUsage = testingUsage
        self.testingMedia = testingMedia
        self.testingClock = testingClock
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                sectionHeader(highlight.eyebrow, detail: highlight.detail(at: date), color: highlight.color)
                highlightCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            runningPanel
                .frame(width: 204)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var highlight: SummaryHighlight {
        SummaryHighlight.select(
            schedule: schedule,
            pullRequests: pullRequests,
            agents: agentSessions,
            actions: testingActions ?? gitHubModel.actionSessions,
            media: testingMedia ?? mediaPlaybackModel.playback,
            usage: usageAvailability,
            clock: testingClock ?? clockModel.status(at: date, includePaused: true),
            priorities: priorities,
            at: date
        )
    }

    private var schedule: CalendarEventSchedule? {
        if let testingSchedule { return testingSchedule }
        guard case let .loaded(schedule) = calendarModel.state else { return nil }
        return schedule
    }

    private var pullRequests: [GitHubPullRequest] {
        if let testingPullRequests { return testingPullRequests }
        guard case let .loaded(pullRequests) = gitHubModel.state else { return [] }
        return pullRequests
    }

    private var agentSessions: [CodingAgentSession] {
        if let testingSessions { return testingSessions }
        guard case let .loaded(sessions) = codingAgentModel.state else { return [] }
        return sessions
    }

    private var usageAvailability: [CodingAgentUsageAvailability] {
        if let testingUsage { return testingUsage }
        guard case let .loaded(availability) = codingAgentModel.usageState else { return [] }
        return availability
    }

    private var runningAgents: [CodingAgentSession] {
        agentSessions.filter { $0.status == .running }
    }

    private var runningActions: [GitHubActionSession] {
        (testingActions ?? gitHubModel.actionSessions).filter { $0.status == .running }
    }

    @ViewBuilder
    private var highlightCard: some View {
        if !canNavigateToHighlight {
            highlightContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(highlight.accessibilityLabel(at: date))
        } else {
            Button { onSelectPage(highlight.destination) } label: {
                highlightContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel(highlight.accessibilityLabel(at: date))
            .accessibilityHint("Opens the related page")
        }
    }

    private var canNavigateToHighlight: Bool {
        highlight.destination != .summary && availablePages.contains(highlight.destination)
    }

    private var highlightContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: highlight.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(highlight.color)
                    .frame(width: 30, height: 30)
                    .background(highlight.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlight.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.85)
                        .monospacedDigit()
                    Text(highlight.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if let percentage = highlight.remainingPercentage {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(percentage)%")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(highlight.color)
                    Text("left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var tileFill: Color { .white.opacity(contrast == .increased ? 0.14 : 0.08) }

    private func sectionHeader(_ title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(detail)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: 16)
    }

    private var runningPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader(
                "ACTIVITY",
                detail: runningAgents.isEmpty && runningActions.isEmpty
                    ? "Idle" : "\(runningAgents.count + runningActions.count) running",
                color: .secondary
            )
            if runningAgents.isEmpty && runningActions.isEmpty {
                quietState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 7) {
                        ForEach(runningAgents) { agentRow($0) }
                        ForEach(runningActions) { actionRow($0) }
                    }
                }
            }
        }
    }

    private var quietState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing running")
                .font(.callout.weight(.semibold))
            Text("Agents and Actions are idle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func agentRow(_ session: CodingAgentSession) -> some View {
        Button { onSelectPage(.agents) } label: {
            activityRow(color: session.kind.notchColor) {
                AgentActivityOrbit(color: session.kind.notchColor, reduceMotion: reduceMotion, size: 22)
                    .accessibilityHidden(true)
            } title: {
                session.title
            } subtitle: {
                workspaceName(session) ?? session.kind.displayName
            }
        }
        .buttonStyle(.plain)
        .disabled(!availablePages.contains(.agents))
        .accessibilityLabel("\(session.kind.displayName) agent running, \(session.title), \(workspaceName(session) ?? session.kind.displayName)")
        .accessibilityHint(availablePages.contains(.agents) ? "Opens the agents page" : "")
    }

    private func actionRow(_ session: GitHubActionSession) -> some View {
        Button { onSelectPage(.github) } label: {
            activityRow(color: .orange) {
                NotchIndicatorView(
                    indicator: NotchIndicator(
                        id: session.id,
                        content: .githubActions(.running),
                        accessibilityLabel: "Running"
                    ),
                    reduceMotion: reduceMotion
                )
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            } title: {
                session.run.name
            } subtitle: {
                actionContext(session.run)
            }
        }
        .buttonStyle(.plain)
        .disabled(!availablePages.contains(.github))
        .accessibilityLabel("GitHub Action \(session.run.name) running, \(actionContext(session.run))")
        .accessibilityHint(availablePages.contains(.github) ? "Opens the GitHub page" : "")
    }

    private func activityRow<Icon: View>(
        color: Color,
        @ViewBuilder icon: () -> Icon,
        title: () -> String,
        subtitle: () -> String
    ) -> some View {
        HStack(spacing: 9) {
            icon()
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title())
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private func actionContext(_ run: GitHubActionRun) -> String {
        if let number = run.pullRequestNumber {
            return "\(run.repository) #\(number)"
        }
        if let ref = run.ref { return "\(run.repository) · \(ref)" }
        return run.repository
    }

    private func workspaceName(_ session: CodingAgentSession) -> String? {
        guard let directory = session.workingDirectory else { return nil }
        let name = URL(fileURLWithPath: directory).lastPathComponent
        return name.isEmpty ? directory : name
    }

}

private extension SummaryHighlight {
    var destination: NotchPage {
        switch self {
        case .event: .calendar
        case .pullRequest: .github
        case .media: .media
        case .clock: .clock
        case .usage: .agents
        case .allClear: .summary
        }
    }

    var eyebrow: String {
        switch self {
        case .event: "UP NEXT"
        case .pullRequest: "GITHUB"
        case .media: "NOW PLAYING"
        case .allClear: "SUMMARY"
        case .clock: "CLOCK"
        case .usage: "USAGE"
        }
    }

    var symbolName: String {
        switch self {
        case .event: "calendar"
        case let .pullRequest(pullRequest): pullRequest.needsAttention ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90" : "arrow.triangle.pull"
        case .media: "waveform"
        case .allClear: "checkmark"
        case let .clock(status): status.mode.symbolName
        case .usage: "gauge.with.dots.needle.67percent"
        }
    }

    var color: Color {
        switch self {
        case let .event(event): Color(red: event.calendarColor.red, green: event.calendarColor.green, blue: event.calendarColor.blue)
        case let .pullRequest(pullRequest): pullRequest.needsAttention ? .red : .orange
        case .media: .purple
        case .allClear: .green
        case .clock: .orange
        case let .usage(kind, _): kind.notchColor
        }
    }

    var title: String {
        switch self {
        case let .event(event): event.title
        case let .pullRequest(pullRequest): pullRequest.title
        case let .media(playback): playback.title
        case .allClear: "All clear"
        case let .clock(status): ClockTimeFormatter.display(status.time, showsTenths: status.mode == .stopwatch)
        case let .usage(_, window): "\(Self.windowName(window).capitalized) limit"
        }
    }

    var subtitle: String {
        switch self {
        case let .event(event): event.location ?? event.calendarName
        case let .pullRequest(pullRequest): "\(pullRequest.repository) #\(pullRequest.number)"
        case let .media(playback): playback.artist.isEmpty ? "Unknown artist" : playback.artist
        case .allClear: "No upcoming events or work needing attention"
        case let .clock(status): status.mode.name
        case let .usage(_, window):
            window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" }
                ?? "Reset time unavailable"
        }
    }

    func detail(at date: Date) -> String {
        switch self {
        case let .event(event):
            if event.isInProgress(relativeTo: date) { return "Now" }
            if Calendar.autoupdatingCurrent.isDate(event.startsAt, inSameDayAs: date) {
                return event.startsAt.formatted(date: .omitted, time: .shortened)
            }
            return event.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case let .pullRequest(pullRequest): return pullRequest.needsAttention ? "Needs attention" : "Open"
        case let .media(playback): return playback.isPlaying ? "Playing" : "Paused"
        case .allClear: return "Quiet"
        case let .clock(status): return status.isRunning ? "Running" : "Paused"
        case let .usage(kind, _): return kind.displayName
        }
    }

    func accessibilityLabel(at date: Date) -> String {
        [eyebrow, title, remainingPercentage.map { "\($0) percent left" }, detail(at: date), subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    var remainingPercentage: Int? {
        guard case let .usage(_, window) = self else { return nil }
        return Int(window.remainingPercent.rounded())
    }

    private static func windowName(_ window: CodingAgentUsage.Window) -> String {
        if let label = window.label { return label }
        switch window.durationMinutes {
        case 300: return "5-hour"
        case 10_080: return "weekly"
        case let minutes?: return "\(max(minutes / 60, 1))-hour"
        case nil: return "usage"
        }
    }
}

private extension GitHubPullRequest {
    var needsAttention: Bool {
        if reviewStatus == .changesRequested { return true }
        if case .failed = actionStatus { return true }
        return false
    }
}
