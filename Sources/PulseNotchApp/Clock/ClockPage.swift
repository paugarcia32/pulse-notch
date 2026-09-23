import SwiftUI

struct ClockPage: View {
    @ObservedObject var model: ClockFeatureModel
    let testingStatus: ClockStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

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

    private var tileFill: Color { .white.opacity(contrast == .increased ? 0.14 : 0.08) }

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
            .accessibilityLabel(ClockStatus(mode: selectedMode, time: time, isRunning: isRunning).accessibilityLabel)

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
                Circle().stroke(.white.opacity(0.1), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: model.timerDuration > 0 ? min(max(time / model.timerDuration, 0), 1) : 0)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: time)
                Image(systemName: isRunning ? "pause.fill" : "timer")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .frame(width: 154, height: 154)
            .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityHidden(true)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("LAPS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    if !model.laps.isEmpty {
                        Text("\(model.laps.count) recorded")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 16)
                if model.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "flag")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("No laps yet").font(.callout.weight(.semibold))
                        Text("Record a lap while running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tileFill, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(model.lapDurations.enumerated()), id: \.offset) { index, duration in
                                HStack {
                                    Text("Lap \(model.laps.count - index)")
                                    Spacer(minLength: 4)
                                    Text(ClockTimeFormatter.display(duration, showsTenths: true))
                                        .monospacedDigit()
                                }
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(tileFill, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Lap \(model.laps.count - index), \(ClockTimeFormatter.accessible(duration))")
                            }
                        }
                    }
                }
            }
            .frame(width: 180)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
