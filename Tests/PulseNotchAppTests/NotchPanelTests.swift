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
    func panelRejectsSizeChangesButCanMove() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 250))

        panel.setFrame(NSRect(x: 40, y: 50, width: 200, height: 40), display: false)
        #expect(panel.frame == NSRect(x: 0, y: 0, width: 500, height: 250))

        panel.setFrame(NSRect(x: 40, y: 50, width: 500, height: 250), display: false)
        #expect(panel.frame == NSRect(x: 40, y: 50, width: 500, height: 250))
    }

    @Test
    func expandedPanelAlwaysReceivesMouseEvents() {
        let frame = NSRect(x: 100, y: 100, width: 200, height: 40)

        #expect(!shouldIgnoreMouseEvents(
            isExpanded: true,
            interactiveFrame: frame,
            pointerLocation: NSPoint(x: 0, y: 0)
        ))
    }

    @Test
    func collapsedPanelOnlyReceivesMouseEventsOverCompactSurface() {
        let frame = NSRect(x: 100, y: 100, width: 200, height: 40)

        #expect(!shouldIgnoreMouseEvents(
            isExpanded: false,
            interactiveFrame: frame,
            pointerLocation: NSPoint(x: 150, y: 120)
        ))
        #expect(shouldIgnoreMouseEvents(
            isExpanded: false,
            interactiveFrame: frame,
            pointerLocation: NSPoint(x: 50, y: 120)
        ))
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
