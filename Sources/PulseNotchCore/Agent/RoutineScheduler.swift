import Foundation

public struct RoutineEvaluation: Hashable, Sendable {
    /// Occurrences that should start now.
    public var due: [RoutineOccurrence] = []
    /// The latest occurrence per routine that passed while Pulse Notch was not
    /// running or the Mac was asleep. They are offered with Run now, never replayed.
    public var missed: [RoutineOccurrence] = []
    /// Occurrences skipped because the same routine was still running.
    public var overlapping: [RoutineOccurrence] = []

    public init(due: [RoutineOccurrence] = [], missed: [RoutineOccurrence] = [], overlapping: [RoutineOccurrence] = []) {
        self.due = due
        self.missed = missed
        self.overlapping = overlapping
    }
}

/// Pure scheduling rules for routines. Every input that depends on time is injected.
public struct RoutineScheduler: Sendable {
    /// How late an occurrence may start and still count as on time, for example
    /// after a short timer delay. Anything later is reported as missed.
    public let gracePeriod: TimeInterval

    public init(gracePeriod: TimeInterval = 5 * 60) {
        self.gracePeriod = gracePeriod
    }

    /// Occurrences scheduled after `start` and up to and including `end`.
    public func occurrences(of routine: Routine, after start: Date, through end: Date) -> [RoutineOccurrence] {
        guard !routine.weekdays.isEmpty, start < end else { return [] }
        let calendar = Self.calendar(for: routine.timeZone)
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        var result: [RoutineOccurrence] = []
        while day <= lastDay {
            if let occurrence = occurrence(of: routine, onDayStarting: day, calendar: calendar),
               occurrence.scheduledAt > start, occurrence.scheduledAt <= end {
                result.append(occurrence)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return result
    }

    public func nextOccurrence(of routine: Routine, after date: Date) -> RoutineOccurrence? {
        guard routine.isEnabled, !routine.weekdays.isEmpty else { return nil }
        let calendar = Self.calendar(for: routine.timeZone)
        var day = calendar.startOfDay(for: date)
        for _ in 0..<15 {
            if let occurrence = occurrence(of: routine, onDayStarting: day, calendar: calendar),
               occurrence.scheduledAt > date {
                return occurrence
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = calendar.startOfDay(for: next)
        }
        return nil
    }

    /// Classifies the occurrences between two evaluations.
    ///
    /// - Parameters:
    ///   - lastEvaluatedAt: When the previous evaluation ran, persisted across launches.
    ///   - handled: Occurrences that already started, were dismissed, or were skipped.
    ///   - activeRoutineIDs: Routines that currently have a run in progress.
    public func evaluate(
        routines: [Routine],
        lastEvaluatedAt: Date,
        now: Date,
        handled: Set<OccurrenceKey>,
        activeRoutineIDs: Set<UUID>
    ) -> RoutineEvaluation {
        var evaluation = RoutineEvaluation()
        for routine in routines where routine.isEnabled {
            let pending = occurrences(of: routine, after: lastEvaluatedAt, through: now)
                .filter { !handled.contains($0.key) }
            var latestMissed: RoutineOccurrence?
            for occurrence in pending {
                if now.timeIntervalSince(occurrence.scheduledAt) > gracePeriod {
                    latestMissed = occurrence
                } else if activeRoutineIDs.contains(routine.id) || evaluation.due.contains(where: { $0.key.routineID == routine.id }) {
                    evaluation.overlapping.append(occurrence)
                } else {
                    evaluation.due.append(occurrence)
                }
            }
            if let latestMissed { evaluation.missed.append(latestMissed) }
        }
        evaluation.due.sort { $0.scheduledAt < $1.scheduledAt }
        evaluation.missed.sort { $0.scheduledAt < $1.scheduledAt }
        return evaluation
    }

    /// The earliest upcoming occurrence across routines, for arming a timer.
    public func nextFireDate(for routines: [Routine], after date: Date) -> Date? {
        routines.compactMap { nextOccurrence(of: $0, after: date)?.scheduledAt }.min()
    }

    private func occurrence(of routine: Routine, onDayStarting day: Date, calendar: Calendar) -> RoutineOccurrence? {
        // Noon is unaffected by daylight-saving transitions, so it gives a reliable weekday.
        guard
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: noon)),
            routine.weekdays.contains(weekday),
            // `.nextTime` moves a time skipped by a spring-forward gap to the next
            // valid instant; `.first` picks the earlier of a repeated fall-back hour.
            let scheduled = calendar.date(
                bySettingHour: routine.time.hour,
                minute: routine.time.minute,
                second: 0,
                of: day,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: noon)
        let localDate = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return RoutineOccurrence(key: OccurrenceKey(routineID: routine.id, localDate: localDate), scheduledAt: scheduled)
    }

    private static func calendar(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
