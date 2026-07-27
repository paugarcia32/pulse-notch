import SwiftUI

@main
struct PulseNotchApp: App {
    var body: some Scene {
        WindowGroup {
            NotchPreview()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

