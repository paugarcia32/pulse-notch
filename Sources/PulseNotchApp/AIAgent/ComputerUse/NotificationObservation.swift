import Foundation

/// Removes its notification observer when released.
final class NotificationObservation: @unchecked Sendable {
    // NotificationCenter is thread-safe, and both references are immutable.
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(
        center: NotificationCenter,
        name: Notification.Name,
        queue: OperationQueue? = nil,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: queue, using: handler)
    }

    deinit {
        center.removeObserver(token)
    }
}
