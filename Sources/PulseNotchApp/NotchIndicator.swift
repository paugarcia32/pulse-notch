import PulseNotchCore
import SwiftUI

struct NotchIndicator: Identifiable {
    enum Content {
        case upcomingCalendarEvent
        case runningAgent(CodingAgentKind)
        case completedAgent(CodingAgentKind)
    }

    let id: String
    let content: Content
    let accessibilityLabel: String

    var color: Color {
        switch content {
        case .upcomingCalendarEvent: .orange
        case .runningAgent(.codex): .cyan
        case .runningAgent(.claude): .orange
        case .runningAgent(.cursor): .purple
        case .runningAgent(.antigravity): .indigo
        case .runningAgent(.opencode): .mint
        case .completedAgent: .green
        }
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
        switch kind {
        case .codex: .white.opacity(0.85)
        case .claude: .orange
        case .cursor: .purple
        case .antigravity: .indigo
        case .opencode: .mint
        }
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
