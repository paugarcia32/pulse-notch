import PulseNotchCore
import SwiftUI

struct CodingAgentsPage: View {
    @ObservedObject var model: CodingAgentFeatureModel
    let date: Date
    let testingSessions: [CodingAgentSession]?

    @State private var showsSetup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

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

        return HStack(alignment: .top, spacing: 12) {
            agentsPanel(activeSessions)
            usagePanel()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func agentsPanel(_ sessions: [CodingAgentSession]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("AGENTS", detail: sessions.isEmpty ? "Idle" : "\(sessions.count) running")
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

    private var tileFill: Color { .white.opacity(contrast == .increased ? 0.14 : 0.08) }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(detail)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: 16)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No agents running").font(.callout.weight(.semibold))
            Text("Watching this Mac for coding sessions").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func agentRow(_ session: CodingAgentSession) -> some View {
        let workspace = workspaceName(session)
        return HStack(spacing: 10) {
            AgentActivityOrbit(color: session.kind.notchColor, reduceMotion: reduceMotion, size: 22)
                .frame(width: 32, height: 32)
                .background(session.kind.notchColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(duration(session))
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text([workspace ?? session.kind.displayName, session.gitBranch].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.kind.displayName) running, \(session.title), \(workspace ?? session.kind.displayName)\(session.gitBranch.map { ", branch \($0)" } ?? ""), \(duration(session))")
    }

    @ViewBuilder
    private func usagePanel() -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("LIMITS", detail: "Remaining")
            switch model.usageState {
            case .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(availability):
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        if availability.isEmpty {
                            usageMessage("No usage data available", symbol: "gauge.with.dots.needle.67percent")
                        } else {
                            ForEach(availability) { status in
                                switch status {
                                case let .available(usage): usageRow(usage)
                                case let .unavailable(kind): unavailableUsageRow(kind)
                                }
                            }
                        }
                        setupOptions(excluding: Set(availability.map(\.kind)))
                    }
                }
            case .unavailable:
                usageMessage("Usage limits are unavailable", symbol: "exclamationmark.triangle")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AgentMark(kind: kind, size: 15)
                Text(kind.displayName).font(.caption.weight(.semibold)).lineLimit(1)
            }
            Text(unavailableDescription(kind))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func usageGauge(_ window: CodingAgentUsage.Window, kind: CodingAgentKind) -> some View {
        let remaining = Int(window.remainingPercent.rounded())
        let reset = Self.resetDescription(window, at: date)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(kind.displayName) · \(windowName(window))")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(remaining)%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(kind.notchColor)
                    .monospacedDigit()
                    .fixedSize()
            }
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(kind.notchColor)
                .scaleEffect(x: 1, y: 0.65, anchor: .center)
                .accessibilityHidden(true)
            if !reset.isEmpty {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.displayName), \(windowName(window)) limit, \(remaining) percent remaining\(reset.isEmpty ? "" : ", \(reset)")")
    }

    private func usageMessage(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
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

    static func resetDescription(_ window: CodingAgentUsage.Window, at date: Date) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        let seconds = Int(resetsAt.timeIntervalSince(date))
        guard seconds > 0 else { return "resets soon" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h" }
        let minutes = seconds / 60
        return minutes > 0 ? "resets in \(minutes)m" : "resets soon"
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
