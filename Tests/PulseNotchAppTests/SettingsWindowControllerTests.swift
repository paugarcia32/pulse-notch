import AppKit
import SwiftUI
import Testing
@testable import PulseNotchApp

@MainActor
struct SettingsWindowControllerTests {
    @Test
    func settingsWindowStartsWithTransparentTitlebarAndFullSizeContent() throws {
        let defaults = try #require(UserDefaults(suiteName: "SettingsWindowControllerTests.\(UUID().uuidString)"))
        let controller = SettingsWindowController(
            preferences: NotchPreferences(defaults: defaults),
            updateModel: UpdateFeatureModel(
                provider: UnavailableReleaseProvider(),
                currentVersion: AppVersion(major: 1, minor: 0, patch: 0),
                defaults: defaults
            ),
            displays: []
        )
        let window = try #require(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.toolbar == nil)
        #expect(window.contentView is NSHostingView<PreferencesView>)
        let contentView = try #require(window.contentView)
        let frameView = try #require(contentView.superview)
        #expect(contentView.frame.height == frameView.bounds.height)
    }
}

private actor UnavailableReleaseProvider: AppReleaseProviding {
    enum Error: Swift.Error { case unavailable }

    func latestRelease() async throws -> AppRelease {
        throw Error.unavailable
    }
}
