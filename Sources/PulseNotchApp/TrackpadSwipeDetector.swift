@preconcurrency import AppKit
import SwiftUI

struct HorizontalSwipeTracker {
    private(set) var accumulatedX: CGFloat = 0
    private(set) var hasTriggered = false

    mutating func update(
        deltaX: CGFloat,
        deltaY: CGFloat,
        began: Bool
    ) -> TrackpadSwipeDetector.Direction? {
        if began {
            accumulatedX = 0
            hasTriggered = false
        }
        guard !hasTriggered, abs(deltaX) > abs(deltaY) else {
            return nil
        }

        accumulatedX += deltaX
        guard abs(accumulatedX) >= 35 else {
            return nil
        }

        hasTriggered = true
        return accumulatedX < 0 ? .left : .right
    }
}

struct TrackpadSwipeDetector: NSViewRepresentable {
    enum Direction: Equatable {
        case left
        case right
    }

    let onSwipe: (Direction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipe: onSwipe)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var onSwipe: (Direction) -> Void

        private weak var view: NSView?
        private var monitor: Any?
        private var swipeTracker = HorizontalSwipeTracker()

        init(onSwipe: @escaping (Direction) -> Void) {
            self.onSwipe = onSwipe
        }

        func install(for view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard
                let view,
                event.window === view.window,
                view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            else {
                return
            }

            guard let direction = swipeTracker.update(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                began: event.phase.contains(.began)
            ) else {
                return
            }
            onSwipe(direction)
        }
    }
}
