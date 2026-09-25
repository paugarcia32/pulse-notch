import AppKit

/// Remembers the last active app other than Pulse Notch, because the agent's own
/// notch panel may be key while the user expects the agent to act on that app.
@MainActor
final class FrontmostApplicationTracker {
    struct Application: Equatable, Sendable {
        let processID: pid_t
        let bundleID: String?
        let name: String?

        init(processID: pid_t, bundleID: String?, name: String?) {
            self.processID = processID
            self.bundleID = bundleID
            self.name = name
        }

        init(_ application: NSRunningApplication) {
            self.init(
                processID: application.processIdentifier,
                bundleID: application.bundleIdentifier,
                name: application.localizedName
            )
        }
    }

    private let ownProcessID: pid_t
    private var lastExternalApplication: Application?
    private var activationObservation: NotificationObservation?

    init(ownProcessID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownProcessID = ownProcessID
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != ownProcessID {
            lastExternalApplication = Application(frontmost)
        }
        activationObservation = NotificationObservation(
            center: NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.didActivateApplicationNotification,
            queue: .main
        ) { [weak self] notification in
            guard let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let application = Application(running)
            MainActor.assumeIsolated { self?.record(application) }
        }
    }

    func targetApplication() -> Application? {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != ownProcessID {
            let application = Application(frontmost)
            lastExternalApplication = application
            return application
        }
        if let last = lastExternalApplication,
           let running = NSRunningApplication(processIdentifier: last.processID),
           !running.isTerminated {
            return last
        }
        if let owner = NSWorkspace.shared.menuBarOwningApplication, owner.processIdentifier != ownProcessID {
            return Application(owner)
        }
        return nil
    }

    private func record(_ application: Application) {
        guard application.processID != ownProcessID else { return }
        lastExternalApplication = application
    }
}
