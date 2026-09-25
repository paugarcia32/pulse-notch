import AppKit
import ApplicationServices
import CoreGraphics

/// Tracks the two permissions computer use needs. Nothing is requested until the
/// user asks for it; checking status never prompts.
@MainActor
final class ComputerUsePermissions: ObservableObject {
    private static let pollInterval: Duration = .seconds(2)
    private static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    private static let screenRecordingSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    private(set) var isMonitoring = false

    private var activationObservation: NotificationObservation?
    private var pollingTask: Task<Void, Never>?

    init() {
        refresh()
        activationObservation = NotificationObservation(
            center: NotificationCenter.default,
            name: NSApplication.didBecomeActiveNotification,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var allGranted: Bool { accessibilityGranted && screenRecordingGranted }

    func refresh() {
        let accessibility = AXIsProcessTrusted()
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        let screenRecording = CGPreflightScreenCaptureAccess()
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }
    }

    func requestAccessibility() {
        // The string key avoids the non-Sendable imported global `kAXTrustedCheckOptionPrompt`.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    /// macOS reports the new grant only after Pulse Notch relaunches.
    func requestScreenRecording() {
        screenRecordingGranted = CGRequestScreenCaptureAccess()
    }

    func openAccessibilitySettings() {
        open(Self.accessibilitySettingsURL)
    }

    func openScreenRecordingSettings() {
        open(Self.screenRecordingSettingsURL)
    }

    /// Polls while a permission screen is visible, since macOS sends no change notification.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.pollInterval)
                } catch {
                    return
                }
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
