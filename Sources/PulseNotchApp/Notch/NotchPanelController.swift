import AppKit
import Combine
import PulseNotchCore
import SwiftUI

struct NotchSurfaceSize: Equatable {
    static let collapsedIndicatorLaneWidth: CGFloat = 108
    static let physicalNotchContentSpacing: CGFloat = 2
    static let collapsedIndicatorOuterPadding: CGFloat = 10
    static let aiAgentPreferredSize = CGSize(width: 640, height: 520)
    /// Keeps the AI Agent surface clear of the display edges on small screens.
    static let displayMargin = CGSize(width: 32, height: 40)

    let collapsed: CGSize
    let expanded: CGSize
    /// The AI Agent page's larger surface, clamped to the display.
    let aiAgentExpanded: CGSize
    let physicalNotchSize: CGSize?

    init(
        notchWidth: CGFloat?,
        notchHeight: CGFloat?,
        externalTopBarHeight: CGFloat = 24,
        displaySize: CGSize? = nil
    ) {
        if let notchWidth, let notchHeight {
            physicalNotchSize = CGSize(width: notchWidth, height: notchHeight)
            collapsed = CGSize(
                width: notchWidth + 2 * Self.collapsedIndicatorLaneWidth,
                height: max(notchHeight, 28)
            )
        } else {
            physicalNotchSize = nil
            collapsed = CGSize(width: 190, height: externalTopBarHeight)
        }
        expanded = CGSize(width: 500, height: 250)
        let available = displaySize.map {
            CGSize(width: $0.width - Self.displayMargin.width, height: $0.height - Self.displayMargin.height)
        } ?? Self.aiAgentPreferredSize
        aiAgentExpanded = CGSize(
            width: max(expanded.width, min(Self.aiAgentPreferredSize.width, available.width)),
            height: max(expanded.height, min(Self.aiAgentPreferredSize.height, available.height))
        )
    }

    func expanded(for page: NotchPage) -> CGSize {
        page == .aiAgent ? aiAgentExpanded : expanded
    }
}

enum NotchMotion {
    static let duration: TimeInterval = 0.3
    static let animation = Animation.timingCurve(0.4, 0, 0.2, 1, duration: duration)
    static let toggleDebounce: TimeInterval = duration + 0.1
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
    let clockModel = ClockFeatureModel()
    let bluetoothHeadphonesModel = BluetoothHeadphonesFeatureModel(provider: BluetoothHeadphonesProvider())
    let systemActivityModel = SystemActivityFeatureModel()
    let updateModel = UpdateFeatureModel(
        provider: GitHubReleaseProvider(),
        currentVersion: AppVersion(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        ) ?? AppVersion(major: 0, minor: 0, patch: 0)
    )
    let homebrewUpdate = HomebrewUpdateCoordinator()
    let computerUsePermissions = ComputerUsePermissions()
    private let desktopSession = DesktopSessionMonitor()
    private let frontmostApplications = FrontmostApplicationTracker()
    private(set) lazy var aiAgentModel: AIAgentFeatureModel = {
        let session = desktopSession
        return AIAgentFeatureModel.live(
            executor: MacComputerUseExecutor(tracker: frontmostApplications),
            availability: session,
            onComposerFocusChange: { session.setComposerFocused($0) }
        )
    }()
    private var aiAgentObserver: AnyCancellable?
    private var currentPage = NotchPage.summary
    private var pendingResizeTask: Task<Void, Never>?

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchSurface>?
    private var settingsWindowController: SettingsWindowController?

    private static func makeMediaPlaybackProvider() -> any MediaPlaybackProviding {
        if let provider = MediaRemoteAdapterPlaybackProvider() { return provider }
        if let provider = MediaRemotePlaybackProvider() { return provider }
        return UnavailableMediaPlaybackProvider()
    }
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var mouseEventUpdateTimer: Timer?
    private var preferenceObserver: NSObjectProtocol?
    private var shortcutObserver: NSObjectProtocol?
    private var shortcutManager: GlobalShortcutManager?
    private var isExpanded = false
    private var displayedScreenID: String?
    private var lastToggleRequestTime: TimeInterval = -.infinity

    var availableDisplays: [NotchDisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(for: screen) else { return nil }
            return NotchDisplayOption(id: id, name: screen.localizedName)
        }
    }

    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                updateModel: updateModel,
                homebrewUpdate: homebrewUpdate,
                displays: availableDisplays
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
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
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .pulseNotchShortcutsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.registerGlobalShortcuts() }
        }
        installDismissMonitors()
        // Once the panel ignores mouse events it cannot receive the tracking update that re-enables it.
        mouseEventUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMouseEventHandling() }
        }
        shortcutManager = GlobalShortcutManager { [weak self] action in
            self?.performShortcut(action)
        }
        registerGlobalShortcuts()
        updateModel.startAutomaticCheck()
        aiAgentObserver = preferences.$aiAgentEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                Task { await self.aiAgentModel.setEnabled(enabled) }
            }
    }

    /// Stops agent runs and managed local runtimes before quitting, so no model
    /// server or helper outlives Pulse Notch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard preferences.aiAgentEnabled else { return .terminateNow }
        Task {
            await aiAgentModel.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateModel.cancel()
        [localEventMonitor, globalEventMonitor, localMouseMoveMonitor, globalMouseMoveMonitor]
            .compactMap { $0 }
            .forEach(NSEvent.removeMonitor)
        mouseEventUpdateTimer?.invalidate()
        mouseEventUpdateTimer = nil
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        if let shortcutObserver { NotificationCenter.default.removeObserver(shortcutObserver) }
        shortcutManager?.stop()
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        if expanded {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
        }
        updateMouseEventHandling()
    }

    func showPanel(on screen: NSScreen?) {
        guard let screen else { return }
        let size = panelSize(on: screen)
        let panel = NotchPanel(contentRect: frame(for: size, on: screen))
        panel.minSize = size
        panel.maxSize = size
        panel.contentMinSize = size
        panel.contentMaxSize = size
        let hostingView = NotchHostingView(rootView: notchSurface(for: screen), fixedSize: size)
        // The controller is the sole owner of panel geometry. Letting the
        // hosting view derive window constraints from animated SwiftUI content
        // can resize the window reentrantly during AppKit's display cycle.
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.sceneBridgingOptions = []
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hostingView
        displayedScreenID = displayID(for: screen)
        updateMouseEventHandling()
    }

    @objc private func screenParametersDidChange() {
        guard let panel, let screen = displayedScreen() ?? preferredScreen() else { return }
        updateSurface(for: screen)
        position(panel, on: screen, size: panelSize(on: screen))
    }

    @objc private func movePanelToPointerScreen() {
        let requestTime = ProcessInfo.processInfo.systemUptime
        guard requestTime - lastToggleRequestTime > NotchMotion.toggleDebounce else { return }
        lastToggleRequestTime = requestTime

        if isExpanded {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pulseNotchClose, object: nil)
            }
            return
        }

        if let panel,
           let screen = preferredScreen(),
           displayID(for: screen) != displayedScreenID {
            updateSurface(for: screen)
            position(panel, on: screen, size: panelSize(on: screen))
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pulseNotchOpenSurface, object: nil)
        }
    }

    private func applyDisplayPreferences() {
        guard let panel, let screen = preferredScreen() else { return }
        NotificationCenter.default.post(name: .pulseNotchClose, object: nil)
        isExpanded = false
        updateSurface(for: screen)
        position(panel, on: screen, size: panelSize(on: screen))
        updateMouseEventHandling()
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
            clockModel: clockModel,
            bluetoothHeadphonesModel: bluetoothHeadphonesModel,
            systemActivityModel: systemActivityModel,
            preferences: preferences,
            updateModel: updateModel,
            homebrewUpdate: homebrewUpdate,
            aiAgentModel: aiAgentModel,
            computerUsePermissions: computerUsePermissions,
            physicalNotchSize: size.physicalNotchSize,
            collapsedSize: size.collapsed,
            expandedSize: size.expanded,
            aiAgentExpandedSize: size.aiAgentExpanded,
            onExpansionChanged: setExpanded,
            onPageChanged: { [weak self] page in self?.pageDidChange(page) }
        )
    }

    private func updateSurface(for screen: NSScreen) {
        guard let hostingView else { return }
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
            clockModel: clockModel,
            bluetoothHeadphonesModel: bluetoothHeadphonesModel,
            systemActivityModel: systemActivityModel,
            preferences: preferences,
            updateModel: updateModel,
            homebrewUpdate: homebrewUpdate,
            aiAgentModel: aiAgentModel,
            computerUsePermissions: computerUsePermissions,
            physicalNotchSize: size.physicalNotchSize,
            collapsedSize: size.collapsed,
            expandedSize: size.expanded,
            aiAgentExpandedSize: size.aiAgentExpanded,
            onExpansionChanged: setExpanded,
            onPageChanged: { [weak self] page in self?.pageDidChange(page) }
        )
    }

    private func geometry(for screen: NSScreen?) -> NotchSurfaceSize {
        guard let screen else {
            return NotchSurfaceSize(notchWidth: nil, notchHeight: nil)
        }
        let left = screen.auxiliaryTopLeftArea?.width
        let right = screen.auxiliaryTopRightArea?.width
        let width = left.flatMap { left in right.map { screen.frame.width - left - $0 } }
        let height = hasPhysicalNotch(screen: screen) ? screen.safeAreaInsets.top : nil
        return NotchSurfaceSize(
            notchWidth: width,
            notchHeight: height,
            externalTopBarHeight: menuBarHeight(for: screen),
            displaySize: screen.frame.size
        )
    }

    private func panelSize(on screen: NSScreen) -> CGSize {
        geometry(for: screen).expanded(for: currentPage)
    }

    /// Grows the window before a larger page animates in, and shrinks it only
    /// after the smaller page's animation finishes, so content is never clipped.
    private func pageDidChange(_ page: NotchPage) {
        guard page != currentPage else { return }
        currentPage = page
        guard let panel, let screen = displayedScreen() ?? preferredScreen() else { return }
        let target = panelSize(on: screen)
        pendingResizeTask?.cancel()
        if target.width >= panel.frame.width && target.height >= panel.frame.height {
            position(panel, on: screen, size: target)
        } else {
            pendingResizeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchMotion.duration + 0.1))
                guard !Task.isCancelled, let self, let panel = self.panel else { return }
                self.position(panel, on: screen, size: self.panelSize(on: screen))
            }
        }
    }

    private func position(_ panel: NotchPanel, on screen: NSScreen, size: CGSize) {
        let targetFrame = frame(for: size, on: screen)
        panel.lock(to: size)
        displayedScreenID = displayID(for: screen)
        panel.setFrame(targetFrame, display: true)
        panel.orderFrontRegardless()
        updateMouseEventHandling()
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

        let updateMouseEvents: (NSEvent) -> Void = { [weak self] _ in
            self?.updateMouseEventHandling()
        }
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            updateMouseEvents(event)
            return event
        }
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: updateMouseEvents)
    }

    private func updateMouseEventHandling() {
        guard let panel, let screen = displayedScreen() ?? panel.screen ?? preferredScreen() else { return }
        let surfaceSize = geometry(for: screen)
        let interactiveFrame = frame(for: collapsedInteractiveSize(for: surfaceSize), on: screen)
        panel.ignoresMouseEvents = shouldIgnoreMouseEvents(
            isExpanded: isExpanded,
            interactiveFrame: interactiveFrame,
            pointerLocation: NSEvent.mouseLocation
        )
    }

    private func registerGlobalShortcuts() {
        // Only actions that currently apply are registered, so the emergency stop
        // claims its hot key only while the AI Agent is enabled.
        let active = Set(preferences.shortcutActions)
        shortcutManager?.replace(with: preferences.shortcuts.filter { active.contains($0.key) })
    }

    private func performShortcut(_ action: ShortcutAction) {
        if action == .agentEmergencyStop {
            aiAgentModel.stopAll()
        } else if let page = preferences.page(for: action) {
            NotificationCenter.default.post(name: .pulseNotchShow(page), object: nil)
        } else if action == .openNotch {
            NotificationCenter.default.post(name: .pulseNotchOpen, object: nil)
        }
    }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    private var fixedSize = NSSize.zero

    init(rootView: Content, fixedSize: NSSize) {
        super.init(rootView: rootView)
        self.fixedSize = fixedSize
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        fixedSize == .zero ? super.intrinsicContentSize : fixedSize
    }
}

func collapsedInteractiveSize(for surfaceSize: NotchSurfaceSize) -> CGSize {
    surfaceSize.physicalNotchSize ?? surfaceSize.collapsed
}

func shouldIgnoreMouseEvents(isExpanded: Bool, interactiveFrame: NSRect, pointerLocation: NSPoint) -> Bool {
    !isExpanded && !interactiveFrame.contains(pointerLocation)
}

final class NotchPanel: NSPanel {
    private var lockedSize: NSSize?

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
        animationBehavior = .none
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        acceptsMouseMovedEvents = true
        lockedSize = contentRect.size
    }

    /// The only way to change the panel's size. The controller calls it when the
    /// selected page needs a different surface; other resize requests are ignored.
    func lock(to size: NSSize) {
        lockedSize = size
        minSize = size
        maxSize = size
        contentMinSize = size
        contentMaxSize = size
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard lockedSize == nil || frameRect.size == lockedSize else { return }
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        guard lockedSize == nil || frameRect.size == lockedSize else { return }
        super.setFrame(frameRect, display: flag, animate: animateFlag)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
