import Foundation

@MainActor
final class BrightnessChangeMonitor {
    private let onChange: @MainActor () -> Void
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = notificationNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onChange() }
            }
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private var notificationNames: [Notification.Name] {
        [
            Notification.Name("com.apple.BezelEngine.BrightnessChanged"),
            Notification.Name("com.apple.BezelServices.BrightnessChanged"),
            Notification.Name("com.apple.controlcenter.display.brightness"),
            Notification.Name("com.apple.CoreBrightness.DisplayBrightnessChanged")
        ]
    }
}
