import AppKit
import PulseNotchCore
import SwiftUI

struct NotchSurfaceSize: Equatable {
    static let collapsedIndicatorLaneWidth: CGFloat = 108
    static let physicalNotchContentSpacing: CGFloat = 2
    static let collapsedIndicatorOuterPadding: CGFloat = 10

    let collapsed: CGSize
    let expanded: CGSize
    let physicalNotchSize: CGSize?

    init(
        notchWidth: CGFloat?,
        notchHeight: CGFloat?,
        externalTopBarHeight: CGFloat = 24,
        externalStyle: ExternalNotchStyle
    ) {
        if let notchWidth, let notchHeight {
            physicalNotchSize = CGSize(width: notchWidth, height: notchHeight)
            collapsed = CGSize(
                width: notchWidth + 2 * Self.collapsedIndicatorLaneWidth,
                height: max(notchHeight, 28)
            )
        } else {
            physicalNotchSize = nil
            let height = externalTopBarHeight
            switch externalStyle {
            case .capsule: collapsed = CGSize(width: 140, height: height)
            case .rectangle: collapsed = CGSize(width: 190, height: height)
            }
        }
        expanded = CGSize(width: 500, height: 250)
    }
}

struct NotchDisplayOption: Identifiable {
    let id: String
    let name: String
}

@MainActor
final class NotchPanelController: NSObject, NSApplicationDelegate {
    let preferences = NotchPreferences()
    let calendarModel = CalendarFeatureModel(provider: EventKitCalendarProvider())
    let codingAgentModel = CodingAgentFeatureModel(provider: LocalCodingAgentProvider())
    let gitHubModel = GitHubFeatureModel(provider: GitHubCLIProvider())
    let batteryModel = BatteryFeatureModel(provider: IOKitBatteryProvider())
    let volumeModel = VolumeFeatureModel(provider: SystemVolumeProvider())
    let brightnessModel = BrightnessFeatureModel(provider: DisplayBrightnessProvider())
    let downloadModel = DownloadFeatureModel(provider: DownloadsDirectoryProvider())
    let mediaPlaybackModel = MediaPlaybackFeatureModel(provider: makeMediaPlaybackProvider())
    let bluetoothHeadphonesModel = BluetoothHeadphonesFeatureModel(provider: BluetoothHeadphonesProvider())
    let systemActivityModel = SystemActivityFeatureModel()

    private var panel: NotchPanel?

    private static func makeMediaPlaybackProvider() -> any MediaPlaybackProviding {
        if let provider = MediaRemoteAdapterPlaybackProvider() { return provider }
        if let provider = MediaRemotePlaybackProvider() { return provider }
        return UnavailableMediaPlaybackProvider()
    }
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var preferenceObserver: NSObjectProtocol?
    private var isExpanded = false
    private var displayedScreenID: String?

    var availableDisplays: [NotchDisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(for: screen) else { return nil }
            return NotchDisplayOption(id: id, name: screen.localizedName)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.applySystemAppearance()
        showPanel(on: preferredScreen())
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .pulseNotchDisplayPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyDisplayPreferences() }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(movePanelToPointerScreen),
            name: .pulseNotchOpen,
            object: nil
        )
        installDismissMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        [localEventMonitor, globalEventMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        resizePanel(animated: true)
    }

    func showPanel(on screen: NSScreen?) {
        guard let screen else { return }
        let size = geometry(for: screen).collapsed
        let panel = NotchPanel(contentRect: frame(for: size, on: screen))
        panel.contentView = NSHostingView(rootView: notchSurface(for: screen))
        panel.orderFrontRegardless()
        self.panel = panel
        displayedScreenID = displayID(for: screen)
    }

    @objc private func screenParametersDidChange() {
        guard let panel, let screen = displayedScreen() ?? preferredScreen() else { return }
        updateSurface(for: screen)
        position(panel, on: screen, size: isExpanded ? geometry(for: screen).expanded : geometry(for: screen).collapsed, animated: false)
    }

    @objc private func movePanelToPointerScreen() {
        guard let panel, let screen = preferredScreen() else { return }
        updateSurface(for: screen)
        position(panel, on: screen, size: geometry(for: screen).collapsed, animated: false)
    }

    private func applyDisplayPreferences() {
        guard let panel, let screen = preferredScreen() else { return }
        NotificationCenter.default.post(name: .pulseNotchClose, object: nil)
        isExpanded = false
        updateSurface(for: screen)
        position(panel, on: screen, size: geometry(for: screen).collapsed, animated: true)
    }

    private func notchSurface(for screen: NSScreen) -> NotchSurface {
        let size = geometry(for: screen)
        return NotchSurface(
            calendarModel: calendarModel,
            codingAgentModel: codingAgentModel,
            gitHubModel: gitHubModel,
            batteryModel: batteryModel,
            volumeModel: volumeModel,
            brightnessModel: brightnessModel,
            downloadModel: downloadModel,
            mediaPlaybackModel: mediaPlaybackModel,
            bluetoothHeadphonesModel: bluetoothHeadphonesModel,
            systemActivityModel: systemActivityModel,
            preferences: preferences,
            isExternalDisplay: !hasPhysicalNotch(screen: screen),
            physicalNotchSize: size.physicalNotchSize,
            onExpansionChanged: setExpanded
        )
    }

    private func updateSurface(for screen: NSScreen) {
        guard let hostingView = panel?.contentView as? NSHostingView<NotchSurface> else { return }
        let size = geometry(for: screen)
        hostingView.rootView = NotchSurface(
            calendarModel: calendarModel,
            codingAgentModel: codingAgentModel,
            gitHubModel: gitHubModel,
            batteryModel: batteryModel,
            volumeModel: volumeModel,
            brightnessModel: brightnessModel,
            downloadModel: downloadModel,
            mediaPlaybackModel: mediaPlaybackModel,
            bluetoothHeadphonesModel: bluetoothHeadphonesModel,
            systemActivityModel: systemActivityModel,
            preferences: preferences,
            isExternalDisplay: !hasPhysicalNotch(screen: screen),
            physicalNotchSize: size.physicalNotchSize,
            onExpansionChanged: setExpanded
        )
    }

    private func geometry(for screen: NSScreen?) -> NotchSurfaceSize {
        guard let screen else {
            return NotchSurfaceSize(notchWidth: nil, notchHeight: nil, externalStyle: preferences.externalNotchStyle)
        }
        let left = screen.auxiliaryTopLeftArea?.width
        let right = screen.auxiliaryTopRightArea?.width
        let width = left.flatMap { left in right.map { screen.frame.width - left - $0 } }
        let height = hasPhysicalNotch(screen: screen) ? screen.safeAreaInsets.top : nil
        return NotchSurfaceSize(
            notchWidth: width,
            notchHeight: height,
            externalTopBarHeight: menuBarHeight(for: screen),
            externalStyle: preferences.externalNotchStyle
        )
    }

    private func resizePanel(animated: Bool) {
        guard let panel else { return }
        guard let screen = displayedScreen() ?? panel.screen ?? preferredScreen() else { return }
        let size = isExpanded ? geometry(for: screen).expanded : geometry(for: screen).collapsed
        position(panel, on: screen, size: size, animated: animated)
    }

    private func position(_ panel: NSPanel, on screen: NSScreen, size: CGSize, animated: Bool) {
        let targetFrame = frame(for: size, on: screen)
        let changes = {
            panel.setFrame(targetFrame, display: true)
            panel.orderFrontRegardless()
        }
        displayedScreenID = displayID(for: screen)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            changes()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func frame(for size: CGSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func screenAtPointer() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    private func preferredScreen() -> NSScreen? {
        if let id = preferences.preferredDisplayID,
           let screen = NSScreen.screens.first(where: { displayID(for: $0) == id }) {
            return screen
        }
        return screenAtPointer() ?? NSScreen.main
    }

    private func displayID(for screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { String($0.uint32Value) }
    }

    private func hasPhysicalNotch(screen: NSScreen?) -> Bool {
        screen?.safeAreaInsets.top ?? 0 > 0
    }

    private func menuBarHeight(for screen: NSScreen) -> CGFloat {
        screen.frame.maxY - screen.visibleFrame.maxY
    }

    private func displayedScreen() -> NSScreen? {
        guard let displayedScreenID else { return nil }
        return NSScreen.screens.first { displayID(for: $0) == displayedScreenID }
    }

    private func installDismissMonitors() {
        let dismissIfOutside: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isExpanded, event.window !== self.panel else { return }
            NotificationCenter.default.post(name: .pulseNotchClose, object: nil)
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            dismissIfOutside(event)
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: dismissIfOutside)
    }
}

private final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The black SwiftUI surface supplies the physical notch edge. A panel
        // shadow adds a light halo in Dark Mode around this borderless window.
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
