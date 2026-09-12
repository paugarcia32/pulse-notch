import PulseNotchCore
import SwiftUI

struct CodingAgentsPage: View {
    @ObservedObject var model: CodingAgentFeatureModel
    let date: Date

    @State private var showsSetup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                placeholder { ProgressView().controlSize(.small) }
            case let .loaded(sessions):
                content(sessions)
            case .unavailable:
                placeholder {
                    Label("Agent detection is unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func content(_ sessions: [CodingAgentSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coding agents").font(.headline)
                Text(summary(sessions)).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if sessions.isEmpty {
                        Label("No coding agents detected", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { session in agentRow(session) }
                    }
                    usageSection()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func agentRow(_ session: CodingAgentSession) -> some View {
        let running = session.status == .running
        return HStack(spacing: 12) {
            AgentMark(kind: session.kind, size: 19).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).font(.callout.weight(.semibold)).lineLimit(1)
                HStack(spacing: 7) {
                    Label(workspaceName(session) ?? session.kind.displayName,
                          systemImage: workspaceName(session) == nil ? "cpu" : "folder")
                    if let branch = session.gitBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                    Label(duration(session), systemImage: "clock")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            NotchIndicatorView(
                indicator: NotchIndicator(
                    id: session.id,
                    content: running ? .runningAgent(session.kind) : .completedAgent(session.kind),
                    accessibilityLabel: running ? "Running" : "Completed"
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
    private func usageSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Usage limits", systemImage: "chart.pie.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch model.usageState {
            case .loading:
                ProgressView().controlSize(.small)
            case let .loaded(availability):
                ForEach(availability) { status in
                    switch status {
                    case let .available(usage): usageRow(usage)
                    case let .unavailable(kind): unavailableUsageRow(kind)
                    }
                }
                setupOptions(excluding: Set(availability.map(\.kind)))
            case .unavailable:
                Label("Usage limits are unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageRow(_ usage: CodingAgentUsage) -> some View {
        HStack(spacing: 12) {
            AgentMark(kind: usage.kind, size: 15).frame(width: 24)
            Text(usage.kind.displayName).font(.callout.weight(.semibold))
            Spacer(minLength: 8)
            if usage.windows.isEmpty {
                Text(unavailableDescription(usage.kind)).font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    ForEach(usage.windows) { window in
                        usageGauge(window, color: usage.kind.notchColor)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private func unavailableUsageRow(_ kind: CodingAgentKind) -> some View {
        HStack(spacing: 12) {
            AgentMark(kind: kind, size: 15).frame(width: 24)
            Text(kind.displayName).font(.callout.weight(.semibold))
            Spacer(minLength: 8)
            Text(unavailableDescription(kind)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private func usageGauge(_ window: CodingAgentUsage.Window, color: Color) -> some View {
        let remaining = Int(window.remainingPercent.rounded())
        return HStack(spacing: 7) {
            TinyUsageRing(value: window.remainingPercent, color: color)
            Text("\(windowName(window)) \(remaining)%")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityLabel("\(windowName(window)) limit, \(remaining) percent remaining")
    }

    @ViewBuilder
    private func setupOptions(excluding installedKinds: Set<CodingAgentKind>) -> some View {
        let unavailable = CodingAgentKind.allCases.filter { !installedKinds.contains($0) }
        if !unavailable.isEmpty {
            Button("Set up more agents", systemImage: showsSetup ? "chevron.down" : "chevron.right") {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { showsSetup.toggle() }
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
            if showsSetup {
                ForEach(unavailable, id: \.self) { kind in
                    Label(setupInstruction(kind), systemImage: "terminal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coding agents").font(.headline)
            Divider()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func summary(_ sessions: [CodingAgentSession]) -> String {
        let running = sessions.count { $0.status == .running }
        return running == 0 ? (sessions.isEmpty ? "Watching this Mac" : "Recently completed") : "\(running) running"
    }

    private func workspaceName(_ session: CodingAgentSession) -> String? {
        guard let directory = session.workingDirectory else { return nil }
        let name = URL(fileURLWithPath: directory).lastPathComponent
        return name.isEmpty ? directory : name
    }

    private func duration(_ session: CodingAgentSession) -> String {
        let end = if case let .completed(completedAt) = session.status { completedAt } else { date }
        let seconds = max(Int(end.timeIntervalSince(session.startedAt)), 0)
        return seconds >= 3_600 ? "\(seconds / 3_600)h \((seconds % 3_600) / 60)m" : seconds >= 60 ? "\(seconds / 60)m" : "now"
    }

    private func windowName(_ window: CodingAgentUsage.Window) -> String {
        if let label = window.label { return label }
        switch window.durationMinutes {
        case 300: return "5 h"
        case 10_080: return "Week"
        case let minutes?: return "\(max(minutes / 60, 1)) h"
        case nil: return "Limit"
        }
    }

    private func unavailableDescription(_ kind: CodingAgentKind) -> String {
        switch kind {
        case .codex, .antigravity: "Usage unavailable"
        case .claude: "Run /statusline to connect"
        case .cursor: "View monthly usage in Cursor"
        case .opencode: "Usage depends on its configured provider"
        }
    }

    private func setupInstruction(_ kind: CodingAgentKind) -> String {
        switch kind {
        case .codex: "Install the Codex app or CLI."
        case .claude: "Install Claude Code CLI, then connect /statusline."
        case .cursor: "Install cursor-agent, then run cursor-agent login."
        case .antigravity: "Install the agy CLI."
        case .opencode: "Install opencode, then configure a provider with /connect."
        }
    }
}

private struct TinyUsageRing: View {
    let value: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: value / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}
