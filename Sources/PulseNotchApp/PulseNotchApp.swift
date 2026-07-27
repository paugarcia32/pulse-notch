import SwiftUI

@main
struct PulseNotchApp: App {
    @StateObject private var calendarModel = CalendarFeatureModel(
        provider: EventKitCalendarProvider()
    )

    var body: some Scene {
        WindowGroup {
            NotchPreview(calendarModel: calendarModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
