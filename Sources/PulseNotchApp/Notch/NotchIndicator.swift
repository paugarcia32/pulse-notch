import PulseNotchCore
import SwiftUI

extension CodingAgentKind {
    var notchColor: Color {
        switch self {
        case .codex: .cyan
        case .claude: .orange
        case .cursor: .purple
        case .antigravity: .indigo
        case .opencode: .mint
        }
    }
}

struct NotchIndicator: Identifiable {
    enum Content: Equatable {
        case upcomingCalendarEvent
        case runningAgent(CodingAgentKind)
        case completedAgent(CodingAgentKind)
        case githubActions(GitHubPullRequest.ActionStatus)
    }

    let id: String
    let content: Content
    let accessibilityLabel: String

    var color: Color {
        switch content {
        case .upcomingCalendarEvent: .orange
        case let .runningAgent(kind): kind.notchColor
        case .completedAgent: .green
        case .githubActions(.running): .orange
        case .githubActions(.failed): .red
        case .githubActions: .green
        }
    }

}

enum CollapsedNotchIndicators {
    static func make(
        schedule: CalendarEventSchedule?,
        sessions: [CodingAgentSession],
        actionSessions: [GitHubActionSession],
        at date: Date,
        calendarReminderLeadTime: TimeInterval
    ) -> [NotchIndicator] {
        var indicators: [NotchIndicator] = []

        if let event = schedule?.next(after: date), event.startsSoon(
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

        if actionSessions.contains(where: { $0.status == .running }) {
            indicators.append(
                NotchIndicator(
                    id: "github-actions-running",
                    content: .githubActions(.running),
                    accessibilityLabel: "GitHub Actions running"
                )
            )
        } else if actionSessions.contains(where: {
            if case let .completed(status) = $0.status { return status == .failed }
            return false
        }) {
            indicators.append(
                NotchIndicator(
                    id: "github-actions-failed",
                    content: .githubActions(.failed),
                    accessibilityLabel: "GitHub Actions failed"
                )
            )
        }

        indicators.append(contentsOf: sessions.prefix(4).map { session in
            let isRunning = session.status == .running
            return NotchIndicator(
                id: session.id,
                content: isRunning
                    ? .runningAgent(session.kind)
                    : .completedAgent(session.kind),
                accessibilityLabel: "\(session.kind.displayName) agent \(isRunning ? "running" : "completed")"
            )
        })

        return Array(indicators.prefix(5))
    }
}

struct NotchIndicatorView: View {
    let indicator: NotchIndicator
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch indicator.content {
            case .upcomingCalendarEvent:
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(indicator.color)
            case .runningAgent:
                AgentActivityDots(color: indicator.color, reduceMotion: reduceMotion)
            case .completedAgent:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(indicator.color)
            case let .githubActions(status):
                Image(systemName: status == .running ? "arrow.triangle.2.circlepath" : "xmark.octagon.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(indicator.color)
            }
        }
            .accessibilityLabel(indicator.accessibilityLabel)
    }
}

struct AgentMark: View {
    let kind: CodingAgentKind
    let size: CGFloat

    var body: some View {
        Group {
            switch kind {
            case .codex:
                Image(systemName: "circle.hexagongrid.fill")
            case .claude:
                Image(systemName: "asterisk")
            case .cursor:
                Image(systemName: "cursorarrow")
            case .antigravity:
                Text("A")
                    .font(.system(size: size, weight: .bold, design: .rounded))
            case .opencode:
                Image(systemName: "terminal")
            }
        }
        .font(.system(size: size, weight: .medium))
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var color: Color {
        kind == .codex ? .white.opacity(0.85) : kind.notchColor
    }
}

private struct AgentActivityDots: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            dots(activeIndex: nil)
        } else {
            TimelineView(.periodic(from: .now, by: 0.45)) { context in
                dots(activeIndex: Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 3)
            }
        }
    }

    private func dots(activeIndex: Int?) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(activeIndex == nil || activeIndex == index ? 1 : 0.28)
            }
        }
        .frame(width: 17, height: 14)
    }
}
