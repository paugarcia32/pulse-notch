import AppKit
import PulseNotchCore

/// Launches and activates applications, waiting briefly for them to come to the front.
@MainActor
enum ApplicationActivation {
    static let frontmostTimeout: Duration = .seconds(2)
    private static let pollInterval: Duration = .milliseconds(100)

    static func open(applicationAt url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let processID: pid_t
        do {
            processID = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration).processIdentifier
        } catch {
            throw ComputerUseError.targetUnavailable("The application could not be opened.")
        }
        _ = await waitUntilFrontmost(processID)
    }

    static func activate(bundleID: String) async throws {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated }) {
            bringToFront(running)
            _ = await waitUntilFrontmost(running.processIdentifier)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ComputerUseError.applicationNotFound(bundleID)
        }
        try await open(applicationAt: url)
    }

    /// - Returns: Whether the process is frontmost afterwards.
    static func bringToFront(processID: pid_t) async -> Bool {
        if isFrontmost(processID) { return true }
        guard let running = NSRunningApplication(processIdentifier: processID), !running.isTerminated else { return false }
        bringToFront(running)
        return await waitUntilFrontmost(processID)
    }

    static func runningApplicationURL(named name: String) -> URL? {
        NSWorkspace.shared.runningApplications.first { application in
            application.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }?.bundleURL
    }

    private static func bringToFront(_ application: NSRunningApplication) {
        // Since macOS 14 activation is cooperative: the active app must yield first.
        NSApplication.shared.yieldActivation(to: application)
        application.activate(options: [])
    }

    private static func isFrontmost(_ processID: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
    }

    private static func waitUntilFrontmost(_ processID: pid_t) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + frontmostTimeout
        while !isFrontmost(processID) {
            guard clock.now < deadline else { return false }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return false
            }
        }
        return true
    }
}
