import SwiftUI

extension Notification.Name {
    static let pulseNotchOpen = Notification.Name("pulseNotchOpen")
    static let pulseNotchShowCalendar = Notification.Name("pulseNotchShowCalendar")
    static let pulseNotchShowAgents = Notification.Name("pulseNotchShowAgents")
    static let pulseNotchShowGitHub = Notification.Name("pulseNotchShowGitHub")
}

@main
struct PulseNotchApp: App {
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
                gitHubModel: gitHubModel
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Pulse Notch") {
                Button("Open Notch") {
                    NotificationCenter.default.post(name: .pulseNotchOpen, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button("Show Calendar") {
                    NotificationCenter.default.post(name: .pulseNotchShowCalendar, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Coding Agents") {
                    NotificationCenter.default.post(name: .pulseNotchShowAgents, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show GitHub") {
                    NotificationCenter.default.post(name: .pulseNotchShowGitHub, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)
            }
        }
    }
}
