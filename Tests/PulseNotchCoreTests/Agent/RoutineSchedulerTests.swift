import Foundation
import Testing
@testable import PulseNotchCore

struct RoutineSchedulerTests {
    private let scheduler = RoutineScheduler(gracePeriod: 300)

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func routine(
        at time: LocalTime,
        weekdays: Set<Weekday> = Weekday.everyDay,
        timeZone: String = "Europe/Madrid",
        isEnabled: Bool = true
    ) -> Routine {
        Routine(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Inbox",
            instruction: "Summarize my inbox",
            weekdays: weekdays,
            time: time,
            timeZoneIdentifier: timeZone,
            isEnabled: isEnabled,
            createdAt: date("2026-01-01T00:00:00Z")
        )
    }

    @Test
    func dailyRoutineOccursOncePerLocalDay() {
        let occurrences = scheduler.occurrences(
            of: routine(at: LocalTime(hour: 9, minute: 0)),
            after: date("2026-06-01T00:00:00Z"),
            through: date("2026-06-03T23:00:00Z")
        )

        #expect(occurrences.map(\.scheduledAt) == [
            date("2026-06-01T07:00:00Z"),
            date("2026-06-02T07:00:00Z"),
            date("2026-06-03T07:00:00Z")
        ])
        #expect(occurrences.map(\.key.localDate) == ["2026-06-01", "2026-06-02", "2026-06-03"])
    }

    @Test
    func selectedWeekdaysAreRespected() {
        let occurrences = scheduler.occurrences(
            of: routine(at: LocalTime(hour: 9, minute: 0), weekdays: [.monday, .wednesday]),
            after: date("2026-06-01T00:00:00Z"),
            through: date("2026-06-07T23:00:00Z")
        )

        // 1 June 2026 is a Monday.
        #expect(occurrences.map(\.key.localDate) == ["2026-06-01", "2026-06-03"])
    }

    @Test
    func timeSkippedBySpringForwardRunsAtTheNextValidInstant() {
        // Madrid skips 02:00–03:00 on 29 March 2026.
        let occurrences = scheduler.occurrences(
            of: routine(at: LocalTime(hour: 2, minute: 30)),
            after: date("2026-03-28T12:00:00Z"),
            through: date("2026-03-29T12:00:00Z")
        )

        #expect(occurrences.count == 1)
        #expect(occurrences.first?.scheduledAt == date("2026-03-29T01:00:00Z"))
    }

    @Test
    func timeRepeatedByFallBackRunsOnlyOnce() {
        // Madrid repeats 02:00–03:00 on 25 October 2026.
        let occurrences = scheduler.occurrences(
            of: routine(at: LocalTime(hour: 2, minute: 30)),
            after: date("2026-10-24T12:00:00Z"),
            through: date("2026-10-25T12:00:00Z")
        )

        #expect(occurrences.count == 1)
        #expect(occurrences.first?.scheduledAt == date("2026-10-25T00:30:00Z"))
    }

    @Test
    func newYorkDaylightSavingIsHandledInTheRoutinesTimeZone() {
        let occurrences = scheduler.occurrences(
            of: routine(at: LocalTime(hour: 8, minute: 0), timeZone: "America/New_York"),
            after: date("2026-03-07T00:00:00Z"),
            through: date("2026-03-09T23:00:00Z")
        )

        #expect(occurrences.map(\.scheduledAt) == [
            date("2026-03-07T13:00:00Z"),
            date("2026-03-08T12:00:00Z"),
            date("2026-03-09T12:00:00Z")
        ])
    }

    @Test
    func occurrenceWithinTheGracePeriodIsDue() {
        let evaluation = scheduler.evaluate(
            routines: [routine(at: LocalTime(hour: 9, minute: 0))],
            lastEvaluatedAt: date("2026-06-01T06:59:00Z"),
            now: date("2026-06-01T07:01:00Z"),
            handled: [],
            activeRoutineIDs: []
        )

        #expect(evaluation.due.map(\.key.localDate) == ["2026-06-01"])
        #expect(evaluation.missed.isEmpty)
    }

    @Test
    func handledOccurrencesNeverRunTwice() {
        let routine = routine(at: LocalTime(hour: 9, minute: 0))
        let evaluation = scheduler.evaluate(
            routines: [routine],
            lastEvaluatedAt: date("2026-06-01T06:59:00Z"),
            now: date("2026-06-01T07:01:00Z"),
            handled: [OccurrenceKey(routineID: routine.id, localDate: "2026-06-01")],
            activeRoutineIDs: []
        )

        #expect(evaluation == RoutineEvaluation())
    }

    @Test
    func occurrencesPassedDuringSleepOrWhileQuitAreMissedNotReplayed() {
        // The Mac slept, or Pulse Notch was not running, for three days.
        let evaluation = scheduler.evaluate(
            routines: [routine(at: LocalTime(hour: 9, minute: 0))],
            lastEvaluatedAt: date("2026-06-01T06:00:00Z"),
            now: date("2026-06-04T06:00:00Z"),
            handled: [],
            activeRoutineIDs: []
        )

        #expect(evaluation.due.isEmpty)
        #expect(evaluation.missed.map(\.key.localDate) == ["2026-06-03"])
    }

    @Test
    func runningRoutinesDoNotOverlap() {
        let routine = routine(at: LocalTime(hour: 9, minute: 0))
        let evaluation = scheduler.evaluate(
            routines: [routine],
            lastEvaluatedAt: date("2026-06-01T06:59:00Z"),
            now: date("2026-06-01T07:00:30Z"),
            handled: [],
            activeRoutineIDs: [routine.id]
        )

        #expect(evaluation.due.isEmpty)
        #expect(evaluation.overlapping.map(\.key.localDate) == ["2026-06-01"])
    }

    @Test
    func disabledRoutinesNeverFire() {
        let disabled = routine(at: LocalTime(hour: 9, minute: 0), isEnabled: false)

        #expect(scheduler.nextOccurrence(of: disabled, after: date("2026-06-01T00:00:00Z")) == nil)
        #expect(scheduler.evaluate(
            routines: [disabled],
            lastEvaluatedAt: date("2026-06-01T06:59:00Z"),
            now: date("2026-06-01T07:01:00Z"),
            handled: [],
            activeRoutineIDs: []
        ) == RoutineEvaluation())
    }

    @Test
    func changingTheSystemTimeZoneDoesNotMoveARoutinesLocalTime() {
        // The routine keeps its own IANA zone; only the evaluation instant changes.
        let routine = routine(at: LocalTime(hour: 9, minute: 0), timeZone: "Asia/Tokyo")
        let next = scheduler.nextOccurrence(of: routine, after: date("2026-06-01T01:00:00Z"))

        #expect(next?.scheduledAt == date("2026-06-02T00:00:00Z"))
        #expect(scheduler.nextFireDate(for: [routine], after: date("2026-06-01T01:00:00Z")) == next?.scheduledAt)
    }
}
