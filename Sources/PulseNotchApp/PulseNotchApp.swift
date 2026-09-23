import AppKit
import SwiftUI

extension Notification.Name {
    static let pulseNotchOpen = Notification.Name("pulseNotchOpen")
    static let pulseNotchOpenSurface = Notification.Name("pulseNotchOpenSurface")
    static let pulseNotchShowSummary = Notification.Name("pulseNotchShowSummary")
    static let pulseNotchShowCalendar = Notification.Name("pulseNotchShowCalendar")
    static let pulseNotchShowAgents = Notification.Name("pulseNotchShowAgents")
    static let pulseNotchShowGitHub = Notification.Name("pulseNotchShowGitHub")
    static let pulseNotchShowMedia = Notification.Name("pulseNotchShowMedia")
    static let pulseNotchShowClock = Notification.Name("pulseNotchShowClock")
    static let pulseNotchShowDownloads = Notification.Name("pulseNotchShowDownloads")
    static let pulseNotchClose = Notification.Name("pulseNotchClose")
    static let pulseNotchDisplayPreferencesChanged = Notification.Name("pulseNotchDisplayPreferencesChanged")
    static let pulseNotchShortcutsChanged = Notification.Name("pulseNotchShortcutsChanged")
}

@main
struct PulseNotchApp: App {
    @NSApplicationDelegateAdaptor(NotchPanelController.self) private var notchController

    var body: some Scene {
        MenuBarExtra(
            "Pulse Notch",
            systemImage: "waveform.path.ecg",
            isInserted: Binding(
                get: { !notchController.preferences.hideFromMenuBar },
                set: { isInserted in
                    let shouldHide = !isInserted
                    guard notchController.preferences.hideFromMenuBar != shouldHide else { return }
                    notchController.preferences.hideFromMenuBar = shouldHide
                }
            )
        ) {
            Button("Open Notch") {
                NotificationCenter.default.post(name: .pulseNotchOpen, object: nil)
            }
            UpdateMenuItem(model: notchController.updateModel)
            Button("Settings…") { notchController.showSettings() }
            Divider()
            Button("Quit Pulse Notch") { NSApplication.shared.terminate(nil) }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { notchController.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Pulse Notch") {
                Button("Open Notch") {
                    NotificationCenter.default.post(name: .pulseNotchOpen, object: nil)
                }

                Button("Close Notch") {
                    NotificationCenter.default.post(name: .pulseNotchClose, object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])

                Divider()

                ForEach(Array(notchController.preferences.orderedVisiblePages.enumerated()), id: \.element) { index, page in
                    Button("Show \(page.name)") {
                        NotificationCenter.default.post(name: .pulseNotchShow(page), object: nil)
                    }
                    .keyboardShortcut(notchController.preferences.shortcut(for: .page(at: index)).keyboardShortcut)
                }
            }
        }
    }
}

private struct UpdateMenuItem: View {
    @ObservedObject var model: UpdateFeatureModel

    var body: some View {
        if let release = model.availableRelease {
            Button("Version \(release.version.description) Available…") {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }
}

extension Notification.Name {
    static func pulseNotchShow(_ page: NotchPage) -> Notification.Name {
        switch page {
        case .summary: .pulseNotchShowSummary
        case .calendar: .pulseNotchShowCalendar
        case .agents: .pulseNotchShowAgents
        case .github: .pulseNotchShowGitHub
        case .media: .pulseNotchShowMedia
        case .clock: .pulseNotchShowClock
        case .downloads: .pulseNotchShowDownloads
        }
    }
}
