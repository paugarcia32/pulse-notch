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

    @Test
    func explicitCloseWhileHoveredRequiresPointerExitBeforeHoverCanReopen() {
        var state = NotchHoverState()

        state.update(isHovering: true)
        state.notchClosed()

        #expect(!state.canOpen)

        state.update(isHovering: false)
        state.update(isHovering: true)
        state.finishClosing()
        #expect(!state.canOpen)

        state.update(isHovering: false)
        #expect(state.canOpen)
    }

    @Test
    func hoverCanReopenAfterClosingFinishesWithPointerOutside() {
        var state = NotchHoverState()

        state.update(isHovering: true)
        state.notchClosed()
        state.update(isHovering: false)
        state.finishClosing()

        #expect(state.canOpen)
    }
}
