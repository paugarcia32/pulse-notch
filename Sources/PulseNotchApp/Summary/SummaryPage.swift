import PulseNotchCore
import SwiftUI

enum SummaryPriority: String, CaseIterable, Identifiable {
    case calendarEvent
    case githubAttention
    case activeWork
    case media
    case openPullRequest
    case clock

    var id: String { "summary-priority-\(rawValue)" }

    var name: String {
        switch self {
        case .calendarEvent: "Next calendar event"
        case .githubAttention: "GitHub needing attention"
        case .activeWork: "Agents and Actions running"
        case .media: "Now playing"
        case .openPullRequest: "Open pull request"
        case .clock: "Active timer or stopwatch"
        }
    }

    var symbolName: String {
        switch self {
        case .calendarEvent: "calendar"
        case .githubAttention: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .activeWork: "bolt.fill"
        case .media: "waveform"
        case .openPullRequest: "arrow.triangle.pull"
        case .clock: "timer"
        }
    }
}

enum SummaryHighlight: Equatable {
    case event(CalendarEvent)
    case pullRequest(GitHubPullRequest)
    case activeWork(agentCount: Int, actionCount: Int)
    case media(MediaPlaybackStatus)
    case clock(ClockStatus)
    case allClear

    static func select(
        schedule: CalendarEventSchedule?,
        pullRequests: [GitHubPullRequest],
        agents: [CodingAgentSession],
        actions: [GitHubActionSession],
        media: MediaPlaybackStatus?,
        clock: ClockStatus? = nil,
        priorities: [SummaryPriority],
        at date: Date
    ) -> SummaryHighlight {
        let runningAgents = agents.filter { $0.status == .running }.count
        let runningActions = actions.filter { $0.status == .running }.count
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
            case .activeWork:
                if runningAgents + runningActions > 0 {
                    return .activeWork(agentCount: runningAgents, actionCount: runningActions)
                }
            case .media:
                if let media { return .media(media) }
            case .openPullRequest:
                if let pullRequest = pullRequests.first(where: { !$0.needsAttention }) {
                    return .pullRequest(pullRequest)
                }
            case .clock:
                if let clock { return .clock(clock) }
            }
        }
        return .allClear
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
    let onSelectPage: (NotchPage) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            highlightCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            runningPanel
                .frame(width: 204)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: highlight)
    }

    private var highlight: SummaryHighlight {
        SummaryHighlight.select(
            schedule: schedule,
            pullRequests: pullRequests,
            agents: agentSessions,
            actions: gitHubModel.actionSessions,
            media: mediaPlaybackModel.playback,
            clock: clockModel.status(at: date, includePaused: true),
            priorities: priorities,
            at: date
        )
    }

    private var schedule: CalendarEventSchedule? {
        guard case let .loaded(schedule) = calendarModel.state else { return nil }
        return schedule
    }

    private var pullRequests: [GitHubPullRequest] {
        guard case let .loaded(pullRequests) = gitHubModel.state else { return [] }
        return pullRequests
    }

    private var agentSessions: [CodingAgentSession] {
        guard case let .loaded(sessions) = codingAgentModel.state else { return [] }
        return sessions
    }

    private var runningAgents: [CodingAgentSession] {
        agentSessions.filter { $0.status == .running }
    }

    private var runningActions: [GitHubActionSession] {
        gitHubModel.actionSessions.filter { $0.status == .running }
    }

    @ViewBuilder
    private var highlightCard: some View {
        if highlight.destination == .summary {
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

    private var highlightContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(highlight.eyebrow, detail: highlight.detail(at: date))
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Image(systemName: highlight.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(highlight.color)
                    .frame(width: 38, height: 38)
                    .background(highlight.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(highlight.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(highlight.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if highlight.destination != .summary {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var runningPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("RUNNING", detail: "\(runningAgents.count + runningActions.count) active")
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

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.pink)
            Spacer(minLength: 6)
            Text(detail)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var quietState: some View {
        VStack(spacing: 5) {
            Image(systemName: "pause.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Nothing running")
                .font(.callout.weight(.semibold))
            Text("Agents and Actions will appear here")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func agentRow(_ session: CodingAgentSession) -> some View {
        Button { onSelectPage(.agents) } label: {
            HStack(spacing: 8) {
                AgentMark(kind: session.kind, size: 14)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(workspaceName(session) ?? session.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(session.kind.notchColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.kind.displayName) agent running, \(session.title)")
    }

    private func actionRow(_ session: GitHubActionSession) -> some View {
        Button { onSelectPage(.github) } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.runner.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Text("Pull request #\(session.runner.pullRequestNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("GitHub Action \(session.runner.name) running")
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
        case .activeWork: .summary
        case .media: .media
        case .clock: .clock
        case .allClear: .summary
        }
    }

    var eyebrow: String {
        switch self {
        case .event: "UP NEXT"
        case .pullRequest: "GITHUB"
        case .activeWork: "IN PROGRESS"
        case .media: "NOW PLAYING"
        case .allClear: "SUMMARY"
        case .clock: "CLOCK"
        }
    }

    var symbolName: String {
        switch self {
        case .event: "calendar"
        case let .pullRequest(pullRequest): pullRequest.needsAttention ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90" : "arrow.triangle.pull"
        case .activeWork: "bolt.fill"
        case .media: "waveform"
        case .allClear: "checkmark"
        case let .clock(status): status.mode.symbolName
        }
    }

    var color: Color {
        switch self {
        case let .event(event): Color(red: event.calendarColor.red, green: event.calendarColor.green, blue: event.calendarColor.blue)
        case let .pullRequest(pullRequest): pullRequest.needsAttention ? .red : .orange
        case .activeWork: .cyan
        case .media: .purple
        case .allClear: .green
        case .clock: .orange
        }
    }

    var title: String {
        switch self {
        case let .event(event): event.title
        case let .pullRequest(pullRequest): pullRequest.title
        case let .activeWork(agentCount, actionCount):
            Self.workTitle(agentCount: agentCount, actionCount: actionCount)
        case let .media(playback): playback.title
        case .allClear: "All clear"
        case let .clock(status): ClockTimeFormatter.display(status.time, showsTenths: status.mode == .stopwatch)
        }
    }

    var subtitle: String {
        switch self {
        case let .event(event): event.location ?? event.calendarName
        case let .pullRequest(pullRequest): "\(pullRequest.repository) #\(pullRequest.number)"
        case .activeWork: "Live work is grouped on the right"
        case let .media(playback): playback.artist.isEmpty ? "Unknown artist" : playback.artist
        case .allClear: "No upcoming events or work needing attention"
        case let .clock(status): status.mode.name
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
        case let .activeWork(agentCount, actionCount): return "\(agentCount + actionCount) active"
        case let .media(playback): return playback.isPlaying ? "Playing" : "Paused"
        case .allClear: return "Quiet"
        case let .clock(status): return status.isRunning ? "Running" : "Paused"
        }
    }

    func accessibilityLabel(at date: Date) -> String {
        "\(eyebrow), \(title), \(detail(at: date)), \(subtitle)"
    }

    private static func workTitle(agentCount: Int, actionCount: Int) -> String {
        let agents = agentCount == 1 ? "1 agent" : "\(agentCount) agents"
        let actions = actionCount == 1 ? "1 Action" : "\(actionCount) Actions"
        if agentCount == 0 { return actions + " running" }
        if actionCount == 0 { return agents + " running" }
        return agents + " and " + actions
    }
}

private extension GitHubPullRequest {
    var needsAttention: Bool {
        if reviewStatus == .changesRequested { return true }
        if case .failed = actionStatus { return true }
        return false
    }
}
