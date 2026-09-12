import SwiftUI

extension Notification.Name {
    static let pulseNotchOpen = Notification.Name("pulseNotchOpen")
    static let pulseNotchShowCalendar = Notification.Name("pulseNotchShowCalendar")
    static let pulseNotchShowAgents = Notification.Name("pulseNotchShowAgents")
    static let pulseNotchShowGitHub = Notification.Name("pulseNotchShowGitHub")
}

@main
struct PulseNotchApp: App {
    @StateObject private var preferences = NotchPreferences()
    @StateObject private var calendarModel = CalendarFeatureModel(
        provider: EventKitCalendarProvider()
    )
    @StateObject private var codingAgentModel = CodingAgentFeatureModel(
        provider: LocalCodingAgentProvider()
    )
    @StateObject private var gitHubModel = GitHubFeatureModel(provider: GitHubCLIProvider())

    var body: some Scene {
        WindowGroup {
            NotchSurface(
                calendarModel: calendarModel,
                codingAgentModel: codingAgentModel,
                gitHubModel: gitHubModel,
                preferences: preferences
            )
            .task { preferences.applySystemAppearance() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 620, height: 360)
        .commands {
            CommandMenu("Pulse Notch") {
                Button("Open Notch") {
                    NotificationCenter.default.post(name: .pulseNotchOpen, object: nil)
                }
                .keyboardShortcut(preferences.shortcut(for: .openNotch).keyboardShortcut)

                Divider()

                ForEach(Array(preferences.orderedVisiblePages.enumerated()), id: \.element) { index, page in
                    Button("Show \(page.name)") {
                        NotificationCenter.default.post(name: .pulseNotchShow(page), object: nil)
                    }
                    .keyboardShortcut(preferences.shortcut(for: .page(at: index)).keyboardShortcut)
                }
            }
        }

        Settings {
            PreferencesView(preferences: preferences)
        }

        MenuBarExtra(
            "Pulse Notch",
            systemImage: "waveform.path.ecg",
            isInserted: Binding(
                get: { !preferences.hideFromMenuBar },
                set: { isInserted in
                    let shouldHide = !isInserted
                    guard preferences.hideFromMenuBar != shouldHide else { return }
                    preferences.hideFromMenuBar = shouldHide
                }
            )
        ) {
            Button("Open Notch") {
                NotificationCenter.default.post(name: .pulseNotchOpen, object: nil)
            }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Pulse Notch") { NSApplication.shared.terminate(nil) }
        }
    }
}

private extension Notification.Name {
    static func pulseNotchShow(_ page: NotchPage) -> Notification.Name {
        switch page {
        case .calendar: .pulseNotchShowCalendar
        case .agents: .pulseNotchShowAgents
        case .github: .pulseNotchShowGitHub
        }
    }
}
