import Testing
@testable import PulseNotchApp

struct HorizontalSwipeTrackerTests {
    @Test
    func pageNavigationWrapsAtBothEnds() {
        let pages: [NotchPage] = [.summary, .calendar, .agents, .github, .media]

        #expect(wrappingPage(in: pages, from: .media, offset: 1) == .summary)
        #expect(wrappingPage(in: pages, from: .summary, offset: -1) == .media)
    }

    @Test
    func pageNavigationKeepsTheOnlyVisiblePageSelected() {
        #expect(wrappingPage(in: [.calendar], from: .calendar, offset: 1) == .calendar)
        #expect(wrappingPage(in: [.calendar], from: .calendar, offset: -1) == .calendar)
    }

    @Test
    func pageIndicatorOnlyAppearsWhenThereAreMultiplePages() {
        #expect(!shouldShowPageIndicator(for: []))
        #expect(!shouldShowPageIndicator(for: [.summary]))
        #expect(shouldShowPageIndicator(for: [.summary, .calendar]))
    }

    @Test
    func twoFingerHorizontalScrollTriggersOnePageChange() {
        var tracker = HorizontalSwipeTracker()

        #expect(tracker.update(deltaX: -20, deltaY: 2, began: true) == nil)
        #expect(tracker.update(deltaX: -20, deltaY: 1, began: false) == .left)
        #expect(tracker.update(deltaX: -40, deltaY: 0, began: false) == nil)
    }

    @Test
    func verticalScrollDoesNotChangePage() {
        var tracker = HorizontalSwipeTracker()

        #expect(tracker.update(deltaX: 4, deltaY: 20, began: true) == nil)
        #expect(tracker.update(deltaX: 3, deltaY: 18, began: false) == nil)
    }
}
