import AppKit
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
        case upcomingCalendarEvent(minutesUntilStart: Int)
        case runningAgent(CodingAgentKind)
        case completedAgent(CodingAgentKind)
        case githubActions(GitHubPullRequest.ActionStatus)
    }

    let id: String
    let content: Content
    let accessibilityLabel: String

    var color: Color {
        switch content {
        case .upcomingCalendarEvent: .pink
        case let .runningAgent(kind): kind.notchColor
        case .completedAgent: .green
        case .githubActions(.running): .orange
        case .githubActions(.failed): .red
        case .githubActions: .green
        }
    }

    var category: CollapsedNotchIndicatorCategory {
        switch content {
        case .upcomingCalendarEvent: .calendar
        case .githubActions: .githubActions
        case .runningAgent, .completedAgent: .codingAgents
        }
    }

}

enum CollapsedNotchIndicatorCategory: String, CaseIterable, Identifiable {
    case calendar
    case githubActions
    case codingAgents

    var id: String { rawValue }

    var name: String {
        switch self {
        case .calendar: "Calendar reminders"
        case .githubActions: "GitHub Actions"
        case .codingAgents: "Coding agents"
        }
    }

}

enum CollapsedIndicatorPreview: String, CaseIterable, Identifiable {
    case calendar
    case githubActions
    case codex
    case claude
    case cursor
    case antigravity
    case opencode

    var id: String { rawValue }

    var name: String {
        switch self {
        case .calendar: "Calendar countdown"
        case .githubActions: "GitHub Actions"
        case .codex: "Codex agent"
        case .claude: "Claude agent"
        case .cursor: "Cursor agent"
        case .antigravity: "Antigravity agent"
        case .opencode: "OpenCode agent"
        }
    }

    var maximumPreviewCount: Int {
        self == .calendar ? 1 : 5
    }

    func indicator(instance: Int) -> NotchIndicator {
        switch self {
        case .calendar:
            return NotchIndicator(id: "\(rawValue)-\(instance)", content: .upcomingCalendarEvent(minutesUntilStart: 31), accessibilityLabel: "Next calendar event starts in 31 minutes")
        case .githubActions:
            return NotchIndicator(id: "\(rawValue)-\(instance)", content: .githubActions(.running), accessibilityLabel: "GitHub Actions running")
        case .codex: return runningAgent(.codex, instance: instance)
        case .claude: return runningAgent(.claude, instance: instance)
        case .cursor: return runningAgent(.cursor, instance: instance)
        case .antigravity: return runningAgent(.antigravity, instance: instance)
        case .opencode: return runningAgent(.opencode, instance: instance)
        }
    }

    private func runningAgent(_ kind: CodingAgentKind, instance: Int) -> NotchIndicator {
        NotchIndicator(id: "\(rawValue)-\(instance)", content: .runningAgent(kind), accessibilityLabel: "\(kind.displayName) agent running")
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
            let minutesUntilStart = max(1, Int((event.startsAt.timeIntervalSince(date) / 60).rounded(.up)))
            indicators.append(
                NotchIndicator(
                    id: "calendar-\(event.id)",
                    content: .upcomingCalendarEvent(minutesUntilStart: minutesUntilStart),
                    accessibilityLabel: "Next calendar event starts in \(minutesUntilStart) \(minutesUntilStart == 1 ? "minute" : "minutes")"
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
            case let .upcomingCalendarEvent(minutesUntilStart):
                CalendarCountdownIndicator(
                    minutesUntilStart: minutesUntilStart,
                    color: indicator.color,
                    reduceMotion: reduceMotion
                )
            case .runningAgent:
                AgentActivityOrbit(color: indicator.color, reduceMotion: reduceMotion)
            case .completedAgent:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(indicator.color)
                    .symbolEffect(.bounce, value: indicator.content)
            case let .githubActions(status):
                GitHubActionIndicator(status: status, color: indicator.color, reduceMotion: reduceMotion)
            }
        }
            .accessibilityLabel(indicator.accessibilityLabel)
    }
}

struct CalendarCountdownIndicator: View {
    let minutesUntilStart: Int
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        HStack {
            CalendarCountdownIcon(color: color)
            Spacer(minLength: 0)
            CalendarCountdownValue(minutesUntilStart: minutesUntilStart, reduceMotion: reduceMotion)
        }
        .foregroundStyle(color)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: minutesUntilStart)
    }
}

struct CalendarCountdownIcon: View {
    let color: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
            Image(systemName: "clock.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.black)
                .padding(1)
                .background(color, in: Circle())
                .offset(x: 2, y: 2)
        }
        .frame(height: 17)
        .foregroundStyle(color)
    }
}

struct CalendarCountdownValue: View {
    let minutesUntilStart: Int
    let reduceMotion: Bool

    var body: some View {
        Text("\(minutesUntilStart)m")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .contentTransition(reduceMotion ? .identity : .numericText())
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct AgentMark: View {
    let kind: CodingAgentKind
    let size: CGFloat

    var body: some View {
        Group {
            if let iconURL, let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var iconURL: URL? {
        Bundle.module.url(forResource: kind.rawValue, withExtension: "png")
    }
}

private struct AgentActivityOrbit: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            orbit(progress: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                orbit(progress: context.date.timeIntervalSinceReferenceDate / 1.4)
            }
        }
    }

    private func orbit(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 1.3)
            Circle()
                .fill(color)
                .frame(width: 3.5, height: 3.5)
                .offset(y: -5.2)
                .rotationEffect(.degrees(progress * 360))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

private struct GitHubActionIndicator: View {
    let status: GitHubPullRequest.ActionStatus
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        if status == .running, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                symbol(rotation: context.date.timeIntervalSinceReferenceDate / 1.6 * 360)
            }
        } else {
            symbol(rotation: 0)
        }
    }

    private func symbol(rotation: Double) -> some View {
        Image(systemName: status == .running ? "arrow.triangle.2.circlepath" : "xmark.octagon.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
    }
}
