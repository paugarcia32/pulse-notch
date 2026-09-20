import SwiftUI

struct ClockPage: View {
    @ObservedObject var model: ClockFeatureModel
    let testingStatus: ClockStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: ClockFeatureModel, testingStatus: ClockStatus? = nil) {
        self.model = model
        self.testingStatus = testingStatus
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: model.selectedMode == .stopwatch ? 0.1 : 1)) { context in
            HStack(spacing: 16) {
                controls(at: context.date)
                activityDetail(at: context.date)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func controls(at date: Date) -> some View {
        let selectedMode = testingStatus?.mode ?? model.selectedMode
        let time = testingStatus?.time ?? model.time(at: date)
        let isRunning = testingStatus?.isRunning ?? model.isRunning
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(ClockMode.allCases) { candidate in
                    Button { model.selectMode(candidate) } label: {
                        Label(candidate.name, systemImage: candidate.symbolName)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                selectedMode == candidate ? .orange.opacity(0.24) : .white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedMode == candidate ? Color.orange : Color.white.opacity(0.65))
                    .accessibilityAddTraits(selectedMode == candidate ? .isSelected : [])
                }
            }
            .frame(width: 220)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Clock mode")

            Text(ClockTimeFormatter.display(
                time,
                showsTenths: selectedMode == .stopwatch
            ))
            .font(.system(size: 38, weight: .medium, design: .rounded))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .accessibilityLabel(ClockTimeFormatter.accessible(model.time(at: date)))

            if selectedMode == .timer, !isRunning {
                HStack(spacing: 6) {
                    ForEach([1, 5, 10, 25], id: \.self) { minutes in
                        Button("\(minutes)m") { model.setTimerDuration(minutes: minutes) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(isRunning ? "Pause" : "Start") { model.startOrPause(at: date) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.space, modifiers: [])
                Button("Reset") { model.reset() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("r", modifiers: [.command])
                if selectedMode == .stopwatch {
                    Button("Lap") { model.recordLap(at: date) }
                        .buttonStyle(.bordered)
                        .disabled(!model.isRunning)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func activityDetail(at date: Date) -> some View {
        let mode = testingStatus?.mode ?? model.selectedMode
        let time = testingStatus?.time ?? model.time(at: date)
        let isRunning = testingStatus?.isRunning ?? model.isRunning
        if mode == .timer {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: model.timerDuration > 0 ? time / model.timerDuration : 0)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: time)
                Image(systemName: isRunning ? "pause.fill" : "timer")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .frame(width: 154, height: 154)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityHidden(true)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text("LAPS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                if model.laps.isEmpty {
                    ContentUnavailableView("No laps yet", systemImage: "flag", description: Text("Record a lap while the stopwatch is running"))
                        .controlSize(.small)
                } else {
                    ForEach(Array(model.laps.prefix(4).enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("Lap \(model.laps.count - index)")
                            Spacer()
                            Text(ClockTimeFormatter.display(lap, showsTenths: true)).monospacedDigit()
                        }
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(width: 180)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
