import AppKit
import Testing
@testable import PulseNotchApp

@MainActor
struct NotchPanelTests {
    @Test
    func canReceiveKeyboardEventsWithoutActivatingWhileCollapsed() {
        let panel = NotchPanel(contentRect: .zero)

        #expect(panel.canBecomeKey)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }
}
