import PulseNotchCore
import SwiftUI

struct AgentGoalsView: View {
    @ObservedObject var model: AIAgentFeatureModel
    @State private var editing: Goal?
    @State private var inspecting: UUID?
    @State private var history: [AgentRun] = []
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let goal = editing {
            GoalEditor(goal: goal) { saved in
                if let saved { Task { await model.saveGoal(saved) } }
                editing = nil
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GOALS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editing = Goal(title: "", instruction: "", completionCriteria: "", limits: model.settings.limits, createdAt: .now)
                    } label: {
                        Label("New goal", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                if model.goals.isEmpty {
                    Text("Goals are persistent tasks with explicit completion criteria. Saving a goal does not start it; choose Run when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .agentTile(contrast: contrast)
                }
                ScrollView(.vertical) {
                    LazyVStack(spacing: 7) {
                        ForEach(model.goals) { goal in goalCard(goal) }
                    }
                }
            }
        }
    }

    private func goalCard(_ goal: Goal) -> some View {
        let live = model.activeRun(forGoal: goal.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title.isEmpty ? goal.instruction : goal.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(Self.label(for: goal.status))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text("Done when: \(goal.completionCriteria)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let live {
                RunControls(model: model, live: live)
                ActionTimeline(events: live.run.events)
            } else {
                HStack(spacing: 8) {
                    Button { Task { await model.runGoal(goal.id) } } label: { Label("Run", systemImage: "play.fill") }
                    Button { editing = goal } label: { Label("Edit", systemImage: "pencil") }
                    Button { toggleHistory(for: goal.id) } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    Spacer()
                    if goal.status == .running || goal.status == .paused || goal.status == .needsInput {
                        Button { Task { await model.cancelGoal(goal.id) } } label: { Label("Cancel", systemImage: "xmark.circle") }
                    }
                    Button(role: .destructive) { Task { await model.deleteGoal(goal.id) } } label: { Label("Delete", systemImage: "trash") }
                }
                .controlSize(.small)
                .labelStyle(.iconOnly)
            }
            if inspecting == goal.id {
                RunHistoryList(runs: history)
            }
        }
        .agentTile(contrast: contrast)
    }

    private func toggleHistory(for id: UUID) {
        if inspecting == id {
            inspecting = nil
            return
        }
        inspecting = id
        Task { history = await model.runs(forGoal: id) }
    }

    static func label(for status: GoalStatus) -> String {
        switch status {
        case .idle: "Not started"
        case .running: "Running"
        case .paused: "Paused"
        case .needsInput: "Needs input"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

struct GoalEditor: View {
    @State private var goal: Goal
    let onFinish: (Goal?) -> Void

    init(goal: Goal, onFinish: @escaping (Goal?) -> Void) {
        _goal = State(initialValue: goal)
        self.onFinish = onFinish
    }

    var body: some View {
        Form {
            TextField("Title", text: $goal.title)
            TextField("Instruction", text: $goal.instruction, axis: .vertical)
                .lineLimit(2...4)
            TextField("Complete when…", text: $goal.completionCriteria, axis: .vertical)
                .lineLimit(1...3)
            LimitsEditor(limits: $goal.limits)
            HStack {
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onFinish(goal) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(goal.instruction.trimmingCharacters(in: .whitespaces).isEmpty
                        || goal.completionCriteria.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct LimitsEditor: View {
    @Binding var limits: RunLimits

    var body: some View {
        Stepper(value: Binding(get: { limits.maximumActions }, set: { limits.maximumActions = $0 }), in: 1...500, step: 5) {
            Text("At most \(limits.maximumActions) actions")
        }
        Stepper(
            value: Binding(get: { Int(limits.maximumDuration / 60) }, set: { limits.maximumDuration = TimeInterval($0 * 60) }),
            in: 1...120
        ) {
            Text("At most \(Int(limits.maximumDuration / 60)) minutes")
        }
    }
}

struct RunHistoryList: View {
    let runs: [AgentRun]

    var body: some View {
        if runs.isEmpty {
            Text("No runs yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(runs.prefix(10)) { run in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            RunStatusLabel(status: run.status)
                            Spacer()
                            Text(run.startedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if case .completed(let evidence) = run.status, !evidence.isEmpty {
                            Text("Evidence: \(evidence)")
                                .font(.caption2)
                                .textSelection(.enabled)
                        }
                        if case .failed(let message) = run.status {
                            Text(message).font(.caption2).foregroundStyle(.red)
                        }
                        if run.status == .interrupted {
                            Text("Pulse Notch quit during this run. Check the result of its last action before running it again.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        ActionTimeline(events: run.events)
                    }
                }
            }
        }
    }
}
