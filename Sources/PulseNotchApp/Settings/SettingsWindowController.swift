import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        preferences: NotchPreferences,
        updateModel: UpdateFeatureModel,
        homebrewUpdate: HomebrewUpdateCoordinator = HomebrewUpdateCoordinator(),
        displays: [NotchDisplayOption]
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .underPageBackgroundColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.contentView = NSHostingView(rootView: PreferencesView(
            preferences: preferences,
            updateModel: updateModel,
            homebrewUpdate: homebrewUpdate,
            displays: displays
        ))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
