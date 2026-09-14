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
    @Published private(set) var shortcuts: [ShortcutAction: AppShortcut]
    @Published private(set) var startupError: String?
    @Published private(set) var preferredDisplayID: String?
    @Published private(set) var externalNotchStyle: ExternalNotchStyle

    private enum Keys {
        static let pageOrder = "settings.pageOrder"
        static let visiblePages = "settings.visiblePages"
        static let openAtLogin = "settings.openAtLogin"
        static let hideFromDock = "settings.hideFromDock"
        static let hideFromMenuBar = "settings.hideFromMenuBar"
        static let calendarReminderLeadTimeMinutes = "settings.calendarReminderLeadTimeMinutes"
        static let shortcuts = "settings.shortcuts"
        static let preferredDisplayID = "settings.preferredDisplayID"
        static let externalNotchStyle = "settings.externalNotchStyle"
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
        shortcuts = Self.shortcuts(from: defaults.data(forKey: Keys.shortcuts))
        preferredDisplayID = defaults.string(forKey: Keys.preferredDisplayID)
        externalNotchStyle = ExternalNotchStyle(rawValue: defaults.string(forKey: Keys.externalNotchStyle) ?? "") ?? .capsule
        startupError = nil
    }

    var orderedVisiblePages: [NotchPage] { pageOrder.filter { visiblePages.contains($0) } }
    var calendarReminderLeadTime: TimeInterval { TimeInterval(calendarReminderLeadTimeMinutes * 60) }
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
