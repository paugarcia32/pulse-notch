import PulseNotchCore
import SwiftUI

struct CodingAgentsPage: View {
    @ObservedObject var model: CodingAgentFeatureModel
    let date: Date
    let testingSessions: [CodingAgentSession]?

    @State private var showsSetup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: CodingAgentFeatureModel, date: Date, testingSessions: [CodingAgentSession]? = nil) {
        self.model = model
        self.date = date
        self.testingSessions = testingSessions
    }

    var body: some View {
        Group {
            switch testingSessions.map(CodingAgentFeatureModel.State.loaded) ?? model.state {
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
        let activeSessions = sessions.filter { $0.status == .running }

        return HStack(alignment: .top, spacing: 14) {
            agentsPanel(activeSessions)
            usagePanel()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func agentsPanel(_ sessions: [CodingAgentSession]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("ACTIVE AGENTS", detail: sessions.isEmpty ? "Watching" : "\(sessions.count) running")
            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(sessions) { session in agentRow(session) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "terminal")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No agents running").font(.callout.weight(.semibold))
            Text("Watching this Mac for coding sessions").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func agentRow(_ session: CodingAgentSession) -> some View {
        let running = session.status == .running
        return HStack(spacing: 10) {
            statusIcon(session, running: running)
                .frame(width: 24, height: 32)
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
        }
        .padding(9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func statusIcon(_ session: CodingAgentSession, running: Bool) -> some View {
        NotchIndicatorView(
            indicator: NotchIndicator(
                id: session.id,
                content: running ? .runningAgent(session.kind) : .completedAgent(session.kind),
                accessibilityLabel: running ? "Running" : "Completed"
            ),
            reduceMotion: reduceMotion
        )
    }

    @ViewBuilder
    private func usagePanel() -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("USAGE", detail: "Live limits")
            switch model.usageState {
            case .loading:
                ProgressView().controlSize(.small)
            case let .loaded(availability):
                if availability.isEmpty {
                    Text("No usage data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(availability) { status in
                                switch status {
                                case let .available(usage): usageRow(usage)
                                case let .unavailable(kind): unavailableUsageRow(kind)
                                }
                            }
                            setupOptions(excluding: Set(availability.map(\.kind)))
                        }
                    }
                }
            case .unavailable:
                Label("Usage limits are unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 204)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func usageRow(_ usage: CodingAgentUsage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if usage.windows.isEmpty {
                unavailableUsageRow(usage.kind)
            } else {
                ForEach(usage.windows) { window in
                    usageGauge(window, kind: usage.kind)
                }
            }
        }
    }

    private func unavailableUsageRow(_ kind: CodingAgentKind) -> some View {
        HStack(spacing: 12) {
            AgentMark(kind: kind, size: 15)
                .frame(width: 24, height: 24)
            Text(kind.displayName).font(.callout.weight(.semibold))
            Spacer(minLength: 8)
            Text(unavailableDescription(kind)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func usageGauge(_ window: CodingAgentUsage.Window, kind: CodingAgentKind) -> some View {
        let used = Int(window.usedPercent.rounded())
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("\(kind.displayName) · \(windowName(window))")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(usageDetail(window, used: used))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            ProgressView(value: window.usedPercent, total: 100)
                .tint(kind.notchColor)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
        }
        .accessibilityLabel("\(kind.displayName), \(windowName(window)) limit, \(used) percent used\(resetDescription(window).isEmpty ? "" : ", \(resetDescription(window))")")
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
                    HStack(spacing: 8) {
                        AgentMark(kind: kind, size: 16)
                            .frame(width: 24, height: 24)
                        Text(setupInstruction(kind))
                    }
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

    private func usageDetail(_ window: CodingAgentUsage.Window, used: Int) -> String {
        let reset = resetDescription(window)
        return reset.isEmpty ? "\(used)%" : "\(used)% · \(reset)"
    }

    private func resetDescription(_ window: CodingAgentUsage.Window) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let seconds = Int(resetsAt.timeIntervalSince(date))
        guard seconds > 0 else { return "resets soon" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return days > 0 ? "resets in \(days)d \(hours)h" : "resets in \(max(hours, 1))h"
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
