import PulseNotchCore
import SwiftUI

struct AgentRoutinesView: View {
    @ObservedObject var model: AIAgentFeatureModel
    @State private var editing: Routine?
    @State private var inspecting: UUID?
    @State private var history: [AgentRun] = []
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let routine = editing {
            RoutineEditor(routine: routine) { saved in
                if let saved { Task { await model.saveRoutine(saved) } }
                editing = nil
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ROUTINES")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editing = Routine(
                            title: "",
                            instruction: "",
                            time: LocalTime(hour: 9, minute: 0),
                            limits: model.settings.limits,
                            createdAt: .now
                        )
                    } label: {
                        Label("New routine", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                ForEach(model.missedOccurrences, id: \.occurrence.key) { missed in
                    missedBanner(missed)
                }
                if model.routines.isEmpty {
                    Text("Routines run while Pulse Notch is open, even with the notch collapsed. Missed occurrences are offered with Run now instead of replaying automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .agentTile(contrast: contrast)
                }
                ScrollView(.vertical) {
                    LazyVStack(spacing: 7) {
                        ForEach(model.routines) { routine in routineCard(routine) }
                    }
                }
            }
        }
    }

    private func missedBanner(_ missed: MissedOccurrence) -> some View {
        let title = model.routines.first { $0.id == missed.occurrence.key.routineID }?.title ?? "Routine"
        return HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Missed “\(title)” on \(missed.occurrence.scheduledAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
            Spacer()
            Button("Run now") {
                Task { await model.runRoutineNow(missed.occurrence.key.routineID, occurrence: missed.occurrence.key) }
            }
            Button("Dismiss") { Task { await model.dismissMissed(missed.occurrence.key) } }
        }
        .controlSize(.small)
        .padding(8)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func routineCard(_ routine: Routine) -> some View {
        let live = model.activeRun(forRoutine: routine.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(routine.title.isEmpty ? routine.instruction : routine.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { routine.isEnabled },
                    set: { enabled in Task { await model.setRoutineEnabled(routine.id, enabled: enabled) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("\(routine.title) enabled")
            }
            Text(Self.scheduleText(routine) + (model.nextOccurrence(of: routine).map { " · next \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let live {
                RunControls(model: model, live: live)
                ActionTimeline(events: live.run.events)
            } else {
                HStack(spacing: 8) {
                    Button { Task { await model.runRoutineNow(routine.id) } } label: { Label("Run now", systemImage: "play.fill") }
                    Button { editing = routine } label: { Label("Edit", systemImage: "pencil") }
                    Button { toggleHistory(for: routine.id) } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    Spacer()
                    Button(role: .destructive) { Task { await model.deleteRoutine(routine.id) } } label: { Label("Delete", systemImage: "trash") }
                }
                .controlSize(.small)
                .labelStyle(.iconOnly)
            }
            if inspecting == routine.id {
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
        Task { history = await model.runs(forRoutine: id) }
    }

    static func scheduleText(_ routine: Routine) -> String {
        let days: String
        if routine.weekdays == Weekday.everyDay {
            days = "Every day"
        } else if routine.weekdays == Weekday.weekdays {
            days = "Weekdays"
        } else {
            let symbols = Calendar.current.shortWeekdaySymbols
            days = routine.weekdays.sorted().map { symbols[$0.rawValue - 1] }.joined(separator: ", ")
        }
        return "\(days) at \(routine.time.formatted) (\(routine.timeZoneIdentifier))"
    }
}

struct RoutineEditor: View {
    @State private var routine: Routine
    let onFinish: (Routine?) -> Void

    init(routine: Routine, onFinish: @escaping (Routine?) -> Void) {
        _routine = State(initialValue: routine)
        self.onFinish = onFinish
    }

    var body: some View {
        Form {
            TextField("Title", text: $routine.title)
            TextField("Instruction", text: $routine.instruction, axis: .vertical)
                .lineLimit(2...4)
            HStack(spacing: 4) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Toggle(Calendar.current.veryShortWeekdaySymbols[day.rawValue - 1], isOn: Binding(
                        get: { routine.weekdays.contains(day) },
                        set: { isOn in
                            if isOn { routine.weekdays.insert(day) } else { routine.weekdays.remove(day) }
                        }
                    ))
                    .toggleStyle(.button)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day.rawValue - 1])
                }
            }
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .environment(\.timeZone, routine.timeZone)
            Picker("Time zone", selection: $routine.timeZoneIdentifier) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Enabled", isOn: $routine.isEnabled)
            LimitsEditor(limits: $routine.limits)
            HStack {
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onFinish(routine) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(routine.instruction.trimmingCharacters(in: .whitespaces).isEmpty || routine.weekdays.isEmpty)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = routine.timeZone
                return calendar.date(bySettingHour: routine.time.hour, minute: routine.time.minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = routine.timeZone
                let components = calendar.dateComponents([.hour, .minute], from: date)
                routine.time = LocalTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
            }
        )
    }
}
