import AppKit
import ApplicationServices
import Foundation
import PulseNotchCore

/// Observes and controls the active app other than Pulse Notch through the
/// Accessibility API, synthesized input events, and ScreenCaptureKit.
///
/// Accessibility calls run on this actor, off the main actor. Live elements are
/// kept only for the most recent observations and never leave the process.
actor MacComputerUseExecutor: ComputerUseExecutor {
    private struct ObservationRecord {
        let id: UUID
        let windowFrame: ScreenRect?
        let elements: [String: LiveElement]
    }

    private static let retainedObservationCount = 4
    private static let focusSettleDelay: Duration = .milliseconds(50)
    private static let secureFieldMessage = "The agent does not type into secure fields."

    private let tracker: FrontmostApplicationTracker
    private let ownProcessID: pid_t
    private let clock: any AgentClock
    private let locator = ApplicationLocator.standard()
    private let walker = AccessibilityTreeWalker()
    private var records: [ObservationRecord] = []

    init(
        tracker: FrontmostApplicationTracker,
        ownProcessID: pid_t = ProcessInfo.processInfo.processIdentifier,
        clock: any AgentClock = SystemAgentClock()
    ) {
        self.tracker = tracker
        self.ownProcessID = ownProcessID
        self.clock = clock
    }

    // MARK: Observation

    func observe(includeScreenshot: Bool) async throws -> Observation {
        try requireAccessibility()
        guard let target = await tracker.targetApplication() else {
            throw ComputerUseError.targetUnavailable("No application is active.")
        }
        let layout = await DisplayLayout.current()
        let application = AccessibilityNode.application(processID: target.processID)
        let window = application.node(AXName.focusedWindow)
            ?? application.node(AXName.mainWindow)
            ?? application.nodes(AXName.windows).first
        if let window { AXUIElementSetMessagingTimeout(window.element, AccessibilityNode.messagingTimeout) }
        let tree = window.map(walker.walk(root:)) ?? AccessibilityTreeSnapshot()
        try Task.checkCancellation()

        let windowTitle = window?.string(AXName.title)
        let windowFrame = window?.frame
        let windowID = windowFrame.flatMap { frame in
            WindowMatcher.match(Self.onScreenWindows(ownedBy: target.processID), frame: frame, title: windowTitle)
        }
        let displayID = windowFrame.flatMap { layout.display(containingX: $0.midX, y: $0.midY)?.id }
            ?? layout.primary?.id
        let screenshot = includeScreenshot
            ? try await ScreenshotCapturer.capture(displayID: displayID, layout: layout, excludingProcessID: ownProcessID)
            : nil

        let observation = Observation(
            capturedAt: clock.now,
            applicationName: target.name,
            bundleID: target.bundleID,
            processID: target.processID,
            windowTitle: windowTitle,
            windowID: windowID,
            displayID: displayID,
            elements: tree.elements,
            screenshot: screenshot
        )
        records.append(ObservationRecord(
            id: observation.id,
            windowFrame: windowFrame,
            elements: tree.live
        ))
        if records.count > Self.retainedObservationCount {
            records.removeFirst(records.count - Self.retainedObservationCount)
        }
        return observation
    }

    // MARK: Validation

    func validate(_ action: ProposedAction, against observation: Observation) async -> TargetValidation {
        switch action {
        case .openURL(let url):
            return Self.isWebURL(url) ? .valid(action) : .invalid("Only web links can be opened.")
        case .openApplication, .activateApplication, .pressKeys:
            return .valid(action)
        case .typeText(_, nil), .scroll(_, _, nil):
            return .valid(action)
        case .click(let target), .typeText(_, .some(let target)), .scroll(_, _, .some(let target)):
            return await validate(target, for: action)
        }
    }

    private func validate(_ target: ActionTarget, for action: ProposedAction) async -> TargetValidation {
        switch target {
        case .element(let id, let observationID):
            guard let live = liveElement(id, observationID: observationID) else {
                return .stale("Element \(id) is no longer known. Observe again.")
            }
            guard let role = live.node.string(AXName.role), role == live.role else {
                return .stale("Element \(id) is no longer on screen. Observe again.")
            }
            if case .typeText = action, live.isSecure || live.node.isSecure {
                return .invalid(Self.secureFieldMessage)
            }
            if Self.requiresEnabledTarget(action), live.node.attribute(AXName.enabled) as? Bool == false {
                return .stale("Element \(id) is disabled. Observe again.")
            }
            return .valid(action)
        case .point(let x, let y, _, let observationID):
            guard record(for: observationID) != nil else {
                return .stale("The observation for this point is no longer known. Observe again.")
            }
            let layout = await DisplayLayout.current()
            guard layout.display(containingX: x, y: y) != nil else {
                return .stale("The point (\(Int(x)), \(Int(y))) is not on any display.")
            }
            return .valid(action)
        }
    }

    // MARK: Execution

    func execute(_ action: ProposedAction, in observation: Observation) async throws -> ActionResult {
        try Task.checkCancellation()
        switch action {
        case .openApplication(let name):
            guard let url = await applicationURL(named: name) else { throw ComputerUseError.applicationNotFound(name) }
            try await ApplicationActivation.open(applicationAt: url)
        case .activateApplication(let bundleID):
            try await ApplicationActivation.activate(bundleID: bundleID)
        case .openURL(let url):
            guard Self.isWebURL(url) else { throw ComputerUseError.inputFailed("Only web links can be opened.") }
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            guard opened else { throw ComputerUseError.targetUnavailable("The link could not be opened.") }
        case .click(let target):
            try requireAccessibility()
            try click(target)
        case .typeText(let text, let target):
            try requireAccessibility()
            try await type(text, into: target, observation: observation)
        case .pressKeys(let shortcut):
            try requireAccessibility()
            guard let keyCode = KeyCodeMap.keyCode(for: shortcut.key) else {
                throw ComputerUseError.inputFailed("Unknown key “\(shortcut.key)”.")
            }
            try await bringObservedApplicationToFront(observation)
            try InputSynthesizer.press(keyCode: keyCode, flags: KeyCodeMap.flags(for: shortcut.modifiers))
        case .scroll(let direction, let amount, let target):
            try requireAccessibility()
            let point = try target.map(point(for:)) ?? record(for: observation.id)?.windowFrame.map(Self.center(of:))
            try InputSynthesizer.scroll(direction, amount: amount, at: point)
        }
        return ActionResult(summary: action.summary)
    }

    func bundleID(forApplicationNamed name: String) async -> String? {
        await applicationURL(named: name).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private func click(_ target: ActionTarget) throws {
        switch target {
        case .element(let id, let observationID):
            let live = try requireLiveElement(id, observationID: observationID)
            if live.actions.contains(AXName.pressAction), live.node.perform(AXName.pressAction) { return }
            try InputSynthesizer.click(at: point(for: live, id: id))
        case .point(let x, let y, _, _):
            try InputSynthesizer.click(at: CGPoint(x: x, y: y))
        }
    }

    private func type(_ text: String, into target: ActionTarget?, observation: Observation) async throws {
        try await bringObservedApplicationToFront(observation)
        if case .element(let id, let observationID) = target {
            let live = try requireLiveElement(id, observationID: observationID)
            guard !live.isSecure else { throw ComputerUseError.inputFailed(Self.secureFieldMessage) }
            if !live.node.setFocused() {
                try InputSynthesizer.click(at: point(for: live, id: id))
            }
            try await Task.sleep(for: Self.focusSettleDelay)
        } else if case .point(let x, let y, _, _) = target {
            try InputSynthesizer.click(at: CGPoint(x: x, y: y))
            try await Task.sleep(for: Self.focusSettleDelay)
        }
        // Focus can land somewhere other than the requested element, so the check
        // applies to whatever will actually receive the keystrokes.
        if AccessibilityNode.systemWide().node(AXName.focusedElement)?.isSecure == true {
            throw ComputerUseError.inputFailed(Self.secureFieldMessage)
        }
        try await InputSynthesizer.type(text)
    }

    /// Keyboard events go to the frontmost app, which may be Pulse Notch itself.
    private func bringObservedApplicationToFront(_ observation: Observation) async throws {
        guard let processID = observation.processID else {
            throw ComputerUseError.targetUnavailable("The observed application is unknown.")
        }
        guard await ApplicationActivation.bringToFront(processID: processID) else {
            throw ComputerUseError.targetUnavailable("\(observation.applicationName ?? "The application") is not frontmost.")
        }
    }

    // MARK: Lookup

    private func applicationURL(named name: String) async -> URL? {
        if ApplicationLocator.looksLikeBundleIdentifier(name),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            return url
        }
        if let url = locator.candidates(forApplicationNamed: name).first { return url }
        return await ApplicationActivation.runningApplicationURL(named: name)
    }

    private func record(for observationID: UUID) -> ObservationRecord? {
        records.last { $0.id == observationID }
    }

    private func liveElement(_ id: String, observationID: UUID) -> LiveElement? {
        record(for: observationID)?.elements[id]
    }

    private func requireLiveElement(_ id: String, observationID: UUID) throws -> LiveElement {
        guard let live = liveElement(id, observationID: observationID) else {
            throw ComputerUseError.targetUnavailable("Element \(id) is no longer known.")
        }
        return live
    }

    private func point(for target: ActionTarget) throws -> CGPoint {
        switch target {
        case .element(let id, let observationID):
            try point(for: requireLiveElement(id, observationID: observationID), id: id)
        case .point(let x, let y, _, _):
            CGPoint(x: x, y: y)
        }
    }

    private func point(for live: LiveElement, id: String) throws -> CGPoint {
        guard let frame = live.node.frame ?? live.frame else {
            throw ComputerUseError.targetUnavailable("Element \(id) has no position on screen.")
        }
        return Self.center(of: frame)
    }

    private func requireAccessibility() throws {
        guard AXIsProcessTrusted() else { throw ComputerUseError.accessibilityPermissionMissing }
    }

    private static func center(of frame: ScreenRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func requiresEnabledTarget(_ action: ProposedAction) -> Bool {
        switch action {
        case .click, .typeText: true
        case .openApplication, .activateApplication, .openURL, .pressKeys, .scroll: false
        }
    }

    private static func onScreenWindows(ownedBy processID: pid_t) -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard (window["kCGWindowOwnerPID"] as? NSNumber)?.int32Value == processID,
                  (window["kCGWindowLayer"] as? NSNumber)?.intValue == 0,
                  let number = window["kCGWindowNumber"] as? NSNumber,
                  let bounds = window["kCGWindowBounds"] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return WindowCandidate(id: number.uint32Value, frame: ScreenRect(rect), title: window["kCGWindowName"] as? String)
        }
    }
}
