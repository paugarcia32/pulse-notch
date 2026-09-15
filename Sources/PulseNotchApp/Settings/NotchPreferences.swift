import AppKit
import ServiceManagement
import SwiftUI

enum NotchPage: String, CaseIterable, Identifiable {
    case calendar
    case agents
    case github

    var id: String { rawValue }

    var name: String {
        switch self {
        case .calendar: "Calendar"
        case .agents: "Coding Agents"
        case .github: "GitHub"
        }
    }

    var symbolName: String {
        switch self {
        case .calendar: "calendar"
        case .agents: "terminal"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case openNotch
    case firstPage
    case secondPage
    case thirdPage

    var id: String { rawValue }

    static func page(at index: Int) -> ShortcutAction {
        [firstPage, secondPage, thirdPage][index]
    }
}

enum ExternalNotchStyle: String, CaseIterable {
    case capsule
    case rectangle

    var name: String {
        switch self {
        case .capsule: "Compact capsule"
        case .rectangle: "Rectangular notch"
        }
    }
}

enum TestingSystemActivity: Equatable {
    case charging
    case volume
    case brightness
    case bluetoothHeadphones
}

@MainActor
final class NotchPreferences: ObservableObject {
    @Published private(set) var pageOrder: [NotchPage]
    @Published private(set) var visiblePages: Set<NotchPage>
    @Published var openAtLogin: Bool {
        didSet {
            guard !isSynchronizingOpenAtLogin else { return }
            updateOpenAtLogin()
        }
    }
    @Published var hideFromDock: Bool { didSet { updateDockVisibility() } }
    @Published var hideFromMenuBar: Bool { didSet { defaults.set(hideFromMenuBar, forKey: Keys.hideFromMenuBar) } }
    @Published private(set) var calendarReminderLeadTimeMinutes: Int
    @Published private(set) var transientSystemActivityDurationSeconds: Int
    @Published private(set) var showChargingActivity: Bool
    @Published private(set) var showVolumeActivity: Bool
    @Published private(set) var showBrightnessActivity: Bool
    @Published private(set) var showBluetoothHeadphonesActivity: Bool
    @Published private(set) var showDownloads: Bool
    @Published private(set) var downloadsDirectoryPath: String
    @Published private(set) var shortcuts: [ShortcutAction: AppShortcut]
    @Published private(set) var startupError: String?
    @Published private(set) var preferredDisplayID: String?
    @Published private(set) var externalNotchStyle: ExternalNotchStyle
    @Published private(set) var collapsedIndicatorPreviewCounts: [CollapsedIndicatorPreview: Int] = [:]
    @Published private(set) var collapsedIndicatorMaximumPerSide: Int
    @Published private(set) var visibleCollapsedIndicatorCategories: Set<CollapsedNotchIndicatorCategory>
    @Published private(set) var testingFeaturesEnabled: Bool
    @Published private(set) var testingSystemActivity: TestingSystemActivity?
    @Published private(set) var testingSystemActivityTrigger: UUID?

    private enum Keys {
        static let pageOrder = "settings.pageOrder"
        static let visiblePages = "settings.visiblePages"
        static let openAtLogin = "settings.openAtLogin"
        static let hideFromDock = "settings.hideFromDock"
        static let hideFromMenuBar = "settings.hideFromMenuBar"
        static let calendarReminderLeadTimeMinutes = "settings.calendarReminderLeadTimeMinutes"
        static let transientSystemActivityDurationSeconds = "settings.transientSystemActivityDurationSeconds"
        static let showChargingActivity = "settings.showChargingActivity"
        static let showVolumeActivity = "settings.showVolumeActivity"
        static let showBrightnessActivity = "settings.showBrightnessActivity"
        static let showBluetoothHeadphonesActivity = "settings.showBluetoothHeadphonesActivity"
        static let showDownloads = "settings.showDownloads"
        static let downloadsDirectoryPath = "settings.downloadsDirectoryPath"
        static let shortcuts = "settings.shortcuts"
        static let preferredDisplayID = "settings.preferredDisplayID"
        static let externalNotchStyle = "settings.externalNotchStyle"
        static let collapsedIndicatorMaximumPerSide = "settings.collapsedIndicatorMaximumPerSide"
        static let visibleCollapsedIndicatorCategories = "settings.visibleCollapsedIndicatorCategories"
        static let testingFeaturesEnabled = "settings.testingFeaturesEnabled"
    }

    private let defaults: UserDefaults
    private var isSynchronizingOpenAtLogin = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pageOrder = Self.pages(from: defaults.stringArray(forKey: Keys.pageOrder))
        let storedVisiblePages = Self.validPages(from: defaults.stringArray(forKey: Keys.visiblePages))
        visiblePages = storedVisiblePages.isEmpty ? Set(NotchPage.allCases) : Set(storedVisiblePages)
        openAtLogin = defaults.bool(forKey: Keys.openAtLogin)
        hideFromDock = defaults.bool(forKey: Keys.hideFromDock)
        hideFromMenuBar = defaults.bool(forKey: Keys.hideFromMenuBar)
        calendarReminderLeadTimeMinutes = min(max(defaults.object(forKey: Keys.calendarReminderLeadTimeMinutes) as? Int ?? 10, 1), 60)
        transientSystemActivityDurationSeconds = Self.clampedTransientSystemActivityDuration(
            defaults.object(forKey: Keys.transientSystemActivityDurationSeconds) as? Int ?? 3
        )
        showChargingActivity = defaults.object(forKey: Keys.showChargingActivity) as? Bool ?? true
        showVolumeActivity = defaults.object(forKey: Keys.showVolumeActivity) as? Bool ?? true
        showBrightnessActivity = defaults.object(forKey: Keys.showBrightnessActivity) as? Bool ?? true
        showBluetoothHeadphonesActivity = defaults.object(forKey: Keys.showBluetoothHeadphonesActivity) as? Bool ?? true
        showDownloads = defaults.object(forKey: Keys.showDownloads) as? Bool ?? true
        downloadsDirectoryPath = defaults.string(forKey: Keys.downloadsDirectoryPath)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? "/Downloads"
        shortcuts = Self.shortcuts(from: defaults.data(forKey: Keys.shortcuts))
        preferredDisplayID = defaults.string(forKey: Keys.preferredDisplayID)
        externalNotchStyle = ExternalNotchStyle(rawValue: defaults.string(forKey: Keys.externalNotchStyle) ?? "") ?? .capsule
        collapsedIndicatorMaximumPerSide = Self.clampedCollapsedIndicatorMaximum(
            defaults.object(forKey: Keys.collapsedIndicatorMaximumPerSide) as? Int ?? 3
        )
        var collapsedIndicatorCategories = Self.collapsedIndicatorCategories(
            from: defaults.stringArray(forKey: Keys.visibleCollapsedIndicatorCategories)
        )
        if defaults.object(forKey: Keys.showDownloads) == nil {
            collapsedIndicatorCategories.insert(.downloads)
        }
        visibleCollapsedIndicatorCategories = collapsedIndicatorCategories
        testingFeaturesEnabled = defaults.bool(forKey: Keys.testingFeaturesEnabled)
        testingSystemActivity = nil
        testingSystemActivityTrigger = nil
        startupError = nil
    }

    var orderedVisiblePages: [NotchPage] { pageOrder.filter { visiblePages.contains($0) } }
    var calendarReminderLeadTime: TimeInterval { TimeInterval(calendarReminderLeadTimeMinutes * 60) }
    var transientSystemActivityDuration: Duration { .seconds(transientSystemActivityDurationSeconds) }
    var downloadsDirectoryURL: URL { URL(fileURLWithPath: downloadsDirectoryPath, isDirectory: true) }
    var shortcutActions: [ShortcutAction] {
        [.openNotch] + orderedVisiblePages.indices.map(ShortcutAction.page(at:))
    }

    func isVisible(_ page: NotchPage) -> Bool { visiblePages.contains(page) }

    func shortcut(for action: ShortcutAction) -> AppShortcut { shortcuts[action]! }

    func setShortcut(_ shortcut: AppShortcut, for action: ShortcutAction) {
        guard shortcuts[action] != shortcut else { return }
        shortcuts[action] = shortcut
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        defaults.set(data, forKey: Keys.shortcuts)
    }

    func page(for action: ShortcutAction) -> NotchPage? {
        switch action {
        case .openNotch: nil
        case .firstPage: orderedVisiblePages[safe: 0]
        case .secondPage: orderedVisiblePages[safe: 1]
        case .thirdPage: orderedVisiblePages[safe: 2]
        }
    }

    func shortcutTitle(for action: ShortcutAction) -> String {
        action == .openNotch ? "Open notch" : "Page \(shortcutActions.firstIndex(of: action)!): \(page(for: action)!.name)"
    }

    func setVisible(_ page: NotchPage, isVisible: Bool) {
        guard isVisible || visiblePages.count > 1 else { return }
        if isVisible { visiblePages.insert(page) } else { visiblePages.remove(page) }
        defaults.set(pageOrder.filter { visiblePages.contains($0) }.map(\.rawValue), forKey: Keys.visiblePages)
    }

    func setCalendarReminderLeadTimeMinutes(_ minutes: Int) {
        let value = min(max(minutes, 1), 60)
        guard calendarReminderLeadTimeMinutes != value else { return }
        calendarReminderLeadTimeMinutes = value
        defaults.set(value, forKey: Keys.calendarReminderLeadTimeMinutes)
    }

    func setTransientSystemActivityDurationSeconds(_ seconds: Int) {
        let value = Self.clampedTransientSystemActivityDuration(seconds)
        guard transientSystemActivityDurationSeconds != value else { return }
        transientSystemActivityDurationSeconds = value
        defaults.set(value, forKey: Keys.transientSystemActivityDurationSeconds)
    }

    func setShowChargingActivity(_ isShown: Bool) {
        guard showChargingActivity != isShown else { return }
        showChargingActivity = isShown
        defaults.set(isShown, forKey: Keys.showChargingActivity)
    }

    func setShowVolumeActivity(_ isShown: Bool) {
        guard showVolumeActivity != isShown else { return }
        showVolumeActivity = isShown
        defaults.set(isShown, forKey: Keys.showVolumeActivity)
    }

    func setShowBrightnessActivity(_ isShown: Bool) {
        guard showBrightnessActivity != isShown else { return }
        showBrightnessActivity = isShown
        defaults.set(isShown, forKey: Keys.showBrightnessActivity)
    }

    func setShowBluetoothHeadphonesActivity(_ isShown: Bool) {
        guard showBluetoothHeadphonesActivity != isShown else { return }
        showBluetoothHeadphonesActivity = isShown
        defaults.set(isShown, forKey: Keys.showBluetoothHeadphonesActivity)
    }

    func setShowDownloads(_ isShown: Bool) {
        guard showDownloads != isShown else { return }
        showDownloads = isShown
        defaults.set(isShown, forKey: Keys.showDownloads)
    }

    func setDownloadsDirectoryURL(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard downloadsDirectoryPath != path else { return }
        downloadsDirectoryPath = path
        defaults.set(path, forKey: Keys.downloadsDirectoryPath)
    }

    func setPreferredDisplayID(_ displayID: String?) {
        guard preferredDisplayID != displayID else { return }
        preferredDisplayID = displayID
        defaults.set(displayID, forKey: Keys.preferredDisplayID)
        NotificationCenter.default.post(name: .pulseNotchDisplayPreferencesChanged, object: nil)
    }

    func setExternalNotchStyle(_ style: ExternalNotchStyle) {
        guard externalNotchStyle != style else { return }
        externalNotchStyle = style
        defaults.set(style.rawValue, forKey: Keys.externalNotchStyle)
        NotificationCenter.default.post(name: .pulseNotchDisplayPreferencesChanged, object: nil)
    }

    func collapsedIndicatorPreviewCount(_ preview: CollapsedIndicatorPreview) -> Int {
        collapsedIndicatorPreviewCounts[preview, default: 0]
    }

    func setTestingFeaturesEnabled(_ isEnabled: Bool) {
        guard testingFeaturesEnabled != isEnabled else { return }
        testingFeaturesEnabled = isEnabled
        if !isEnabled { collapsedIndicatorPreviewCounts.removeAll() }
        defaults.set(isEnabled, forKey: Keys.testingFeaturesEnabled)
    }

    func setCollapsedIndicatorPreviewCount(_ count: Int, for preview: CollapsedIndicatorPreview) {
        guard testingFeaturesEnabled else { return }
        collapsedIndicatorPreviewCounts[preview] = min(max(count, 0), preview.maximumPreviewCount)
    }

    func triggerTestingSystemActivity(_ activity: TestingSystemActivity) {
        guard testingFeaturesEnabled else { return }
        testingSystemActivity = activity
        testingSystemActivityTrigger = UUID()
    }

    func setCollapsedIndicatorMaximumPerSide(_ maximum: Int) {
        let value = Self.clampedCollapsedIndicatorMaximum(maximum)
        guard collapsedIndicatorMaximumPerSide != value else { return }
        collapsedIndicatorMaximumPerSide = value
        defaults.set(value, forKey: Keys.collapsedIndicatorMaximumPerSide)
    }

    func isCollapsedIndicatorCategoryVisible(_ category: CollapsedNotchIndicatorCategory) -> Bool {
        visibleCollapsedIndicatorCategories.contains(category)
    }

    func setCollapsedIndicatorCategory(_ category: CollapsedNotchIndicatorCategory, isVisible: Bool) {
        if isVisible {
            visibleCollapsedIndicatorCategories.insert(category)
        } else {
            visibleCollapsedIndicatorCategories.remove(category)
        }
        defaults.set(visibleCollapsedIndicatorCategories.map(\.rawValue), forKey: Keys.visibleCollapsedIndicatorCategories)
    }

    func movePages(from offsets: IndexSet, to destination: Int) {
        pageOrder.move(fromOffsets: offsets, toOffset: destination)
        defaults.set(pageOrder.map(\.rawValue), forKey: Keys.pageOrder)
    }

    func applySystemAppearance() {
        updateDockVisibility()
    }

    private func updateOpenAtLogin() {
        defaults.set(openAtLogin, forKey: Keys.openAtLogin)
        do {
            if openAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            startupError = nil
        } catch {
            isSynchronizingOpenAtLogin = true
            openAtLogin = false
            isSynchronizingOpenAtLogin = false
            defaults.set(false, forKey: Keys.openAtLogin)
            startupError = "Pulse Notch could not update the login-item setting."
        }
    }

    private func updateDockVisibility() {
        defaults.set(hideFromDock, forKey: Keys.hideFromDock)
        NSApp.setActivationPolicy(hideFromDock ? .accessory : .regular)
    }

    private static func pages(from storedPages: [String]?) -> [NotchPage] {
        let stored = validPages(from: storedPages)
        return stored.count == NotchPage.allCases.count && Set(stored).count == stored.count
            ? stored
            : NotchPage.allCases
    }

    private static func validPages(from storedPages: [String]?) -> [NotchPage] {
        storedPages?.compactMap(NotchPage.init(rawValue:)) ?? []
    }

    private static func collapsedIndicatorCategories(
        from storedCategories: [String]?
    ) -> Set<CollapsedNotchIndicatorCategory> {
        guard let storedCategories else { return Set(CollapsedNotchIndicatorCategory.allCases) }
        return Set(storedCategories.compactMap(CollapsedNotchIndicatorCategory.init(rawValue:)))
    }

    private static func clampedCollapsedIndicatorMaximum(_ maximum: Int) -> Int {
        min(max(maximum, 1), 5)
    }

    private static func clampedTransientSystemActivityDuration(_ seconds: Int) -> Int {
        min(max(seconds, 1), 10)
    }

    private static func shortcuts(from data: Data?) -> [ShortcutAction: AppShortcut] {
        let stored = data.flatMap { try? JSONDecoder().decode([ShortcutAction: AppShortcut].self, from: $0) } ?? [:]
        return ShortcutAction.allCases.reduce(into: stored) { shortcuts, action in
            if shortcuts[action] == nil { shortcuts[action] = defaultShortcuts[action] }
        }
    }

    private static let defaultShortcuts: [ShortcutAction: AppShortcut] = [
        .openNotch: AppShortcut(key: "n", modifiers: [.command, .option]),
        .firstPage: AppShortcut(key: "1", modifiers: [.command]),
        .secondPage: AppShortcut(key: "2", modifiers: [.command]),
        .thirdPage: AppShortcut(key: "3", modifiers: [.command])
    ]
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
