import AppKit
import Foundation

enum ClockMode: String, CaseIterable, Identifiable {
    case stopwatch
    case timer

    var id: String { rawValue }
    var name: String { self == .stopwatch ? "Stopwatch" : "Timer" }
    var symbolName: String { self == .stopwatch ? "stopwatch" : "timer" }
}

struct ClockStatus: Equatable {
    let mode: ClockMode
    let time: TimeInterval
    let isRunning: Bool

    var accessibilityLabel: String {
        "\(mode.name), \(ClockTimeFormatter.accessible(time))\(isRunning ? ", running" : ", paused")"
    }
}

@MainActor
final class ClockFeatureModel: ObservableObject {
    @Published private(set) var selectedMode = ClockMode.timer
    @Published private(set) var stopwatchStartedAt: Date?
    @Published private(set) var stopwatchElapsed: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []
    @Published private(set) var timerDuration: TimeInterval = 5 * 60
    @Published private(set) var timerEndsAt: Date?
    @Published private(set) var timerRemaining: TimeInterval = 5 * 60

    private var completionTask: Task<Void, Never>?

    var isRunning: Bool {
        selectedMode == .stopwatch ? stopwatchStartedAt != nil : timerEndsAt != nil
    }

    func selectMode(_ mode: ClockMode, at date: Date = .now) {
        guard mode != selectedMode else { return }
        if isRunning { startOrPause(at: date) }
        selectedMode = mode
    }

    func time(at date: Date) -> TimeInterval {
        switch selectedMode {
        case .stopwatch:
            stopwatchElapsed + (stopwatchStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        case .timer:
            timerEndsAt.map { max(0, $0.timeIntervalSince(date)) } ?? timerRemaining
        }
    }

    func status(at date: Date, includePaused: Bool = false) -> ClockStatus? {
        let value = time(at: date)
        let hasPausedActivity = selectedMode == .stopwatch
            ? stopwatchElapsed > 0
            : timerRemaining < timerDuration
        guard isRunning || (includePaused && hasPausedActivity) else { return nil }
        return ClockStatus(mode: selectedMode, time: value, isRunning: isRunning)
    }

    func startOrPause(at date: Date = .now) {
        switch selectedMode {
        case .stopwatch:
            if let startedAt = stopwatchStartedAt {
                stopwatchElapsed += max(0, date.timeIntervalSince(startedAt))
                stopwatchStartedAt = nil
            } else {
                stopwatchStartedAt = date
            }
        case .timer:
            if let endsAt = timerEndsAt {
                timerRemaining = max(0, endsAt.timeIntervalSince(date))
                timerEndsAt = nil
                completionTask?.cancel()
            } else {
                if timerRemaining <= 0 { timerRemaining = timerDuration }
                timerEndsAt = date.addingTimeInterval(timerRemaining)
                scheduleCompletion(after: timerRemaining)
            }
        }
    }

    func reset() {
        completionTask?.cancel()
        switch selectedMode {
        case .stopwatch:
            stopwatchStartedAt = nil
            stopwatchElapsed = 0
            laps = []
        case .timer:
            timerEndsAt = nil
            timerRemaining = timerDuration
        }
    }

    func recordLap(at date: Date = .now) {
        guard stopwatchStartedAt != nil else { return }
        laps.insert(time(at: date), at: 0)
    }

    func setTimerDuration(minutes: Int) {
        guard timerEndsAt == nil else { return }
        timerDuration = TimeInterval(min(max(minutes, 1), 180) * 60)
        timerRemaining = timerDuration
    }

    private func scheduleCompletion(after interval: TimeInterval) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.timerEndsAt = nil
            self?.timerRemaining = 0
            NSSound.beep()
        }
    }
}

enum ClockTimeFormatter {
    static func display(_ interval: TimeInterval, showsTenths: Bool = false) -> String {
        let value = max(0, interval)
        let totalSeconds = Int(value)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        let base = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
        guard showsTenths else { return base }
        return "\(base).\(Int(value * 10) % 10)"
    }

    static func accessible(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval).rounded())
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return [
            hours > 0 ? "\(hours) hours" : nil,
            minutes > 0 ? "\(minutes) minutes" : nil,
            "\(remainder) seconds"
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
