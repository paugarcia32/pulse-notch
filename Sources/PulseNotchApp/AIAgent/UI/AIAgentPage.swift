import PulseNotchCore
import SwiftUI

/// The AI Agent page: chat, goals, routines, and provider settings in the notch.
struct AIAgentPage: View {
    @ObservedObject var model: AIAgentFeatureModel
    @ObservedObject var permissions: ComputerUsePermissions
    let isActive: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let error = model.lastError {
                AgentBanner(text: error, symbol: "exclamationmark.triangle.fill", tint: .orange) {
                    model.dismissError()
                }
            }
            Group {
                switch model.selectedTab {
                case .chat: AgentChatView(model: model, isActive: isActive)
                case .goals: AgentGoalsView(model: model)
                case .routines: AgentRoutinesView(model: model)
                case .settings: AgentSettingsView(model: model, permissions: permissions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if isActive { model.acknowledgeOutcome() } }
        .onChange(of: isActive) { _, active in if active { model.acknowledgeOutcome() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Section", selection: $model.selectedTab) {
                ForEach(AIAgentFeatureModel.Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            Spacer(minLength: 4)

            AgentModeBadge(settings: model.settings)
            if !model.liveRuns.isEmpty {
                Button(role: .destructive) {
                    model.stopAll()
                } label: {
                    Label("Stop all", systemImage: "stop.fill")
                }
                .controlSize(.small)
                .help("Stop every AI Agent run. Completed actions are not undone.")
            }
        }
    }
}

/// States whether inference is fully local, without implying that the task stays offline.
struct AgentModeBadge: View {
    let settings: AIAgentSettings

    var body: some View {
        let local = settings.configuration().isFullyLocalInference
        Label(local ? "Local inference" : "Hosted inference", systemImage: local ? "desktopcomputer" : "cloud")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .help(local
                ? "Both models run on this Mac. Tasks that use online apps still reach the network."
                : "At least one provider is hosted. See Settings for what is sent.")
    }
}

struct AgentBanner: View {
    let text: String
    let symbol: String
    let tint: Color
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(8)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Status text plus a symbol, so state never relies on color alone.
struct RunStatusLabel: View {
    let status: RunStatus

    var body: some View {
        Label(status.label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    private var symbol: String {
        switch status {
        case .queued: "clock"
        case .running: "sparkles"
        case .paused: "pause.circle"
        case .needsInput: "questionmark.bubble"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .stopped: "stop.circle"
        case .interrupted: "bolt.horizontal.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .queued, .stopped, .interrupted: .secondary
        case .running: .teal
        case .paused: .yellow
        case .needsInput: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}

/// Pause, resume, stop, and approval controls for one run.
struct RunControls: View {
    @ObservedObject var model: AIAgentFeatureModel
    let live: LiveRun

    var body: some View {
        HStack(spacing: 6) {
            RunStatusLabel(status: live.run.status)
            if live.run.actionCount > 0 {
                Text("\(live.run.actionCount) actions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if case .needsInput(.approval) = live.run.status {
                Button("Approve") { model.answerApproval(live.id, approved: true) }
                    .keyboardShortcut(.defaultAction)
                Button("Decline") { model.answerApproval(live.id, approved: false) }
            }
            switch live.run.status {
            case .running, .queued:
                Button { model.pause(live.id) } label: { Label("Pause", systemImage: "pause.fill") }
            case .paused, .needsInput:
                if case .needsInput(.approval) = live.run.status {} else {
                    Button { model.resume(live.id) } label: { Label("Resume", systemImage: "play.fill") }
                }
            default:
                EmptyView()
            }
            Button(role: .destructive) { model.stop(live.id) } label: { Label("Stop", systemImage: "stop.fill") }
                .help("Stops further actions and cancels inference. Completed actions are not undone.")
        }
        .controlSize(.small)
        .labelStyle(.iconOnly)
    }
}

/// An expandable list of observed, decided, executed, and verified steps.
struct ActionTimeline: View {
    let events: [ExecutionEvent]
    @State private var isExpanded = false

    var body: some View {
        if !events.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(events.suffix(60)) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: Self.symbol(for: event.kind))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                                .accessibilityHidden(true)
                            Text(event.summary)
                                .font(.caption2)
                                .foregroundStyle(event.kind == .warning ? .orange : .primary)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 2)
            } label: {
                Text("Timeline · \(events.count) steps")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func symbol(for kind: ExecutionEvent.Kind) -> String {
        switch kind {
        case .observed: "eye"
        case .planned: "list.bullet"
        case .decided: "scale.3d"
        case .executed: "cursorarrow.click"
        case .verified: "checkmark.seal"
        case .retried: "arrow.clockwise"
        case .status: "info.circle"
        case .message: "text.bubble"
        case .warning: "exclamationmark.triangle"
        }
    }
}

extension View {
    func agentTile(contrast: ColorSchemeContrast) -> some View {
        padding(10)
            .background(.white.opacity(contrast == .increased ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
