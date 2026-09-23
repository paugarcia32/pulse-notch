import Foundation
import Testing
@testable import PulseNotchApp

@MainActor
struct ClockFeatureModelTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test
    func stopwatchUsesDatesAndPreservesElapsedTimeWhenPaused() {
        let model = ClockFeatureModel()
        model.selectMode(.stopwatch, at: start)

        model.startOrPause(at: start)
        #expect(abs(model.time(at: start.addingTimeInterval(12.4)) - 12.4) < 0.001)

        model.startOrPause(at: start.addingTimeInterval(12.4))
        #expect(abs(model.time(at: start.addingTimeInterval(30)) - 12.4) < 0.001)
        #expect(model.status(at: start, includePaused: true)?.isRunning == false)
    }

    @Test
    func timerCountsDownAndResumesFromItsPausedValue() {
        let model = ClockFeatureModel()
        model.setTimerDuration(minutes: 10)
        model.startOrPause(at: start)

        #expect(model.time(at: start.addingTimeInterval(90)) == 510)

        model.startOrPause(at: start.addingTimeInterval(90))
        model.startOrPause(at: start.addingTimeInterval(200))
        #expect(model.time(at: start.addingTimeInterval(230)) == 480)
    }

    @Test
    func stopwatchRecordsAndClearsLaps() {
        let model = ClockFeatureModel()
        model.selectMode(.stopwatch, at: start)
        model.startOrPause(at: start)
        model.recordLap(at: start.addingTimeInterval(5.5))
        model.recordLap(at: start.addingTimeInterval(8))

        #expect(model.laps == [8, 5.5])

        model.reset()
        #expect(model.laps.isEmpty)
        #expect(model.time(at: start.addingTimeInterval(20)) == 0)
    }

    @Test
    func lapRowsShowIndividualIntervalsInsteadOfCumulativeStopwatchTime() {
        let model = ClockFeatureModel()
        model.selectMode(.stopwatch, at: start)
        model.startOrPause(at: start)
        model.recordLap(at: start.addingTimeInterval(5.5))
        model.recordLap(at: start.addingTimeInterval(8))
        model.recordLap(at: start.addingTimeInterval(12.2))

        #expect(model.lapDurations.count == 3)
        #expect(abs(model.lapDurations[0] - 4.2) < 0.001)
        #expect(ClockTimeFormatter.display(model.lapDurations[0], showsTenths: true) == "00:04.2")
        #expect(model.lapDurations[1] == 2.5)
        #expect(model.lapDurations[2] == 5.5)
    }

    @Test
    func switchingModesPausesTheRunningClock() {
        let model = ClockFeatureModel()
        model.startOrPause(at: start)
        model.selectMode(.stopwatch, at: start.addingTimeInterval(30))

        model.selectMode(.timer, at: start.addingTimeInterval(60))
        #expect(model.time(at: start.addingTimeInterval(90)) == 270)
        #expect(!model.isRunning)
    }

    @Test
    func formatsCompactClockValues() {
        #expect(ClockTimeFormatter.display(65) == "01:05")
        #expect(ClockTimeFormatter.display(3_661) == "1:01:01")
        #expect(ClockTimeFormatter.display(5.59, showsTenths: true) == "00:05.5")
    }
}
