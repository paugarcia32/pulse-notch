import AppKit
import PulseNotchCore
import SwiftUI

private enum SettingsDestination: Hashable {
    case general
    case notch
    case pages
    case page(NotchPage)
    case shortcuts
    case advanced
}

private let settingsSidebarWidth: CGFloat = 200

struct PreferencesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var preferences: NotchPreferences
    @ObservedObject var updateModel: UpdateFeatureModel
    let displays: [NotchDisplayOption]
    @State private var selection = SettingsDestination.general
    @State private var isSidebarVisible = true
    @State private var gitHubRepositoryName = ""
    @State private var gitHubRepositoryError: String?

    var body: some View {
        settingsLayout
            .frame(minWidth: 760, idealWidth: 820, minHeight: 480, idealHeight: 540)
    }

    private var settingsLayout: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        Label("General", systemImage: "gear")
                            .tag(SettingsDestination.general)
                        Label("Notch", systemImage: "macbook")
                            .tag(SettingsDestination.notch)

                        Section("Pages") {
                            Label("Overview", systemImage: "rectangle.3.group")
                                .tag(SettingsDestination.pages)
                            ForEach(preferences.pageOrder) { page in
                                Label(page.name, systemImage: page.symbolName)
                                    .tag(SettingsDestination.page(page))
                            }
                        }

                        Section {
                            Label("Shortcuts", systemImage: "command")
                                .tag(SettingsDestination.shortcuts)
                            Label("Advanced", systemImage: "gearshape.2")
                                .tag(SettingsDestination.advanced)
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)

                    appIdentity
                }
                .frame(width: settingsSidebarWidth)
                .background(.regularMaterial)

                Divider()
            }

            VStack(spacing: 0) {
                detail
            }
        }
        .background(
            SettingsWindowConfigurator(
                title: selection.title,
                isSidebarVisible: isSidebarVisible,
                toggleSidebar: { setSidebarVisible(!isSidebarVisible) }
            )
        )
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        if reduceMotion {
            isSidebarVisible = isVisible
        } else {
            withAnimation(.smooth(duration: 0.3)) {
                isSidebarVisible = isVisible
            }
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pulse Notch")
                    .font(.callout.weight(.semibold))
                Text("Version \(updateModel.currentVersion.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let release = updateModel.availableRelease {
                    Link(destination: release.pageURL) {
                        Label(
                            "Update to \(release.version.description)…",
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .help("Open the release page to update Pulse Notch")
                    .accessibilityLabel("Update Pulse Notch to version \(release.version.description)")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: generalSettings
        case .notch: notchSettings
        case .pages: pagesOverview
        case let .page(page): pageSettings(page)
        case .shortcuts: shortcutSettings
        case .advanced: advancedSettings
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Startup") {
                Toggle("Open at Login", isOn: $preferences.openAtLogin)
                if let startupError = preferences.startupError {
                    Text(startupError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Presence") {
                Toggle("Show in Dock", isOn: showInDock)
                Toggle("Show in Menu Bar", isOn: showInMenuBar)
            }
            Section("Display") {
                Picker("Show Pulse Notch on", selection: preferredDisplayID) {
                    Text("Display under pointer").tag("pointer")
                    ForEach(displays) { Text($0.name).tag($0.id) }
                }
                Picker("External display style", selection: externalNotchStyle) {
                    ForEach(ExternalNotchStyle.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                Text("This setting only affects displays without a physical notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Automatically check for updates", isOn: $updateModel.automaticChecksEnabled)
                LabeledContent("Current version", value: updateModel.currentVersion.description)

                HStack {
                    updateStatus
                    Spacer()
                    Button("Check Now") {
                        updateModel.checkNow()
                    }
                    .disabled(updateModel.state == .checking)
                }

                if let release = updateModel.availableRelease {
                    Link("View Version \(release.version.description)…", destination: release.pageURL)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Pulse Notch checks the latest public GitHub release at most once per day.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateModel.state {
        case .idle:
            Text("Not checked yet")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
            }
            .accessibilityElement(children: .combine)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle")
        case let .available(release):
            Label("Version \(release.version.description) is available", systemImage: "arrow.down.circle")
        case .failed:
            Label("Couldn’t check for updates", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private var notchSettings: some View {
        Form {
            Section {
                Stepper(value: collapsedIndicatorMaximumPerSide, in: 1...5) {
                    Text("Maximum items per side: \(preferences.collapsedIndicatorMaximumPerSide)")
                }
                Button("Restore Default Colors") { preferences.resetCollapsedIndicatorColors() }
                    .disabled(!preferences.hasCustomCollapsedIndicatorColors)
            } header: {
                Text("Closed notch")
            } footer: {
                Text("More than 3 items per side is not recommended. Indicator colors are configured on each page.")
            }
            Section {
                ForEach(Array(preferences.collapsedIndicatorPriorityOrder.enumerated()), id: \.element.id) { index, category in
                    HStack(spacing: 10) {
                        numberedLabel(index + 1, category.name, symbol: category.symbolName)
                        Spacer(minLength: 12)
                        Button {
                            moveCollapsedIndicatorPriority(at: index, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(category.name) up")

                        Button {
                            moveCollapsedIndicatorPriority(at: index, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == preferences.collapsedIndicatorPriorityOrder.count - 1)
                        .accessibilityLabel("Move \(category.name) down")
                    }
                }
            } header: {
                Text("Activity priority")
            } footer: {
                Text("Use the arrows to decide which activities remain visible when space is limited.")
            }
            Section("Temporary system activities") {
                Toggle("Show charging activity", isOn: showChargingActivity)
                Toggle("Show volume activity", isOn: showVolumeActivity)
                Toggle("Show brightness activity", isOn: showBrightnessActivity)
                Toggle("Show Bluetooth headphones activity", isOn: showBluetoothHeadphonesActivity)
                Stepper(value: transientSystemActivityDurationSeconds, in: 1...10) {
                    Text("Show for \(preferences.transientSystemActivityDurationSeconds) seconds")
                }
                .disabled(!hasEnabledSystemActivity)
            }
        }
        .formStyle(.grouped)
    }

    private var pagesOverview: some View {
        Form {
            Section {
                Toggle("Show pages only when active", isOn: dynamicPagesEnabled)
            } footer: {
                Text("When enabled, pages appear only while they have relevant activity. Media remains visible for five minutes after pausing.")
            }
            Section {
                ForEach(Array(preferences.pageOrder.enumerated()), id: \.element.id) { index, page in
                    HStack(spacing: 10) {
                        numberedLabel(index + 1, page.name, symbol: page.symbolName)
                        Spacer()
                        Text(preferences.isVisible(page) ? "Shown" : "Hidden")
                            .foregroundStyle(.secondary)
                        reorderButtons(
                            index: index,
                            count: preferences.pageOrder.count,
                            itemName: page.name,
                            move: movePage
                        )
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = .page(page) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { selection = .page(page) }
                }
            } header: {
                Text("Page order")
            } footer: {
                Text("Use the arrows to reorder. Select a page to configure its visibility and activity.")
            }
        }
        .formStyle(.grouped)
    }

    private func pageSettings(_ page: NotchPage) -> some View {
        Form {
            Section {
                Toggle("Show \(page.name) page", isOn: pageVisibility(page))
                    .disabled(!canHide(page))
            } header: {
                Text("Page")
            } footer: {
                if !canHide(page) {
                    Text("At least one page must remain visible.")
                }
            }

            if page == .summary {
                Section {
                    ForEach(Array(preferences.summaryPriorityOrder.enumerated()), id: \.element.id) { index, priority in
                        HStack(spacing: 10) {
                            numberedLabel(index + 1, priority.name, symbol: priority.symbolName)
                            Spacer(minLength: 12)
                            reorderButtons(
                                index: index,
                                count: preferences.summaryPriorityOrder.count,
                                itemName: priority.name,
                                move: moveSummaryPriority
                            )
                        }
                    }
                } header: {
                    Text("Content priority")
                } footer: {
                    Text("Use the arrows to decide which content fills the Summary page first.")
                }
            }

            if page == .calendar {
                Section("Calendar reminders") {
                    Stepper(value: calendarReminderLeadTimeMinutes, in: 1...60) {
                        Text("Show upcoming events \(preferences.calendarReminderLeadTimeMinutes) minutes before they start")
                    }
                }
            }

            if page == .downloads {
                downloadsSettings
            }

            if page == .github {
                gitHubSettings
            }

            if let category = indicatorCategory(for: page) {
                Section {
                    Toggle("Show \(category.name) when notch is closed", isOn: collapsedIndicatorCategory(category))
                    ColorPicker(selection: collapsedIndicatorColor(category), supportsOpacity: false) {
                        Label("Indicator color", systemImage: category.symbolName)
                    }
                } header: {
                    Text("Closed notch")
                } footer: {
                    Text(indicatorColorDescription(for: category))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var downloadsSettings: some View {
        Section {
            Toggle("Monitor active downloads", isOn: showDownloads)
            Toggle("Monitor Homebrew activity", isOn: showHomebrewDownloads)
                .disabled(!preferences.showDownloads)
            LabeledContent("Watch folder") {
                HStack(spacing: 8) {
                    Text(URL(fileURLWithPath: preferences.downloadsDirectoryPath).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: chooseDownloadsDirectory)
                        .buttonStyle(.bordered)
                }
            }
            if preferences.downloadsDirectoryURL != defaultDownloadsDirectory {
                Button("Use Downloads folder") {
                    preferences.setDownloadsDirectoryURL(defaultDownloadsDirectory)
                }
            }
        } header: {
            Text("Download monitoring")
        } footer: {
            Text("File names, locations, and Homebrew processes are inspected locally and are not persisted. Homebrew progress is shown as indeterminate.")
        }
    }

    private var gitHubSettings: some View {
        Section {
            HStack {
                TextField("owner/repository or GitHub URL", text: $gitHubRepositoryName)
                    .onSubmit(addGitHubRepository)
                Button("Add", action: addGitHubRepository)
                    .buttonStyle(.bordered)
            }

            if let gitHubRepositoryError {
                Text(gitHubRepositoryError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if preferences.monitoredGitHubRepositories.isEmpty {
                Label("No repositories selected", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preferences.monitoredGitHubRepositories) { repository in
                    HStack {
                        Label(repository.nameWithOwner, systemImage: "shippingbox")
                        Spacer()
                        Button {
                            preferences.removeMonitoredGitHubRepository(repository)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Stop monitoring \(repository.nameWithOwner)")
                    }
                }
            }
        } header: {
            Text("GitHub Actions monitoring")
        } footer: {
            Text("Monitors push, tag, and manual runs. Pull request checks stay enabled.")
        }
    }

    private func addGitHubRepository() {
        guard let repository = gitHubRepository else {
            gitHubRepositoryError = "Enter a repository as owner/repository or a GitHub URL."
            return
        }
        guard preferences.addMonitoredGitHubRepository(named: repository.nameWithOwner) else {
            gitHubRepositoryError = "This repository is already being monitored."
            return
        }
        gitHubRepositoryError = nil
        gitHubRepositoryName = ""
    }

    private var gitHubRepository: GitHubRepository? {
        let input = gitHubRepositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let compactInput = input.replacingOccurrences(of: " ", with: "")
        if let repository = GitHubRepository(nameWithOwner: compactInput) {
            return repository
        }

        guard
            let url = URL(string: input),
            let host = url.host?.lowercased(),
            host == "github.com" || host == "www.github.com"
        else { return nil }

        var components = url.path.split(separator: "/").map(String.init)
        guard components.count == 2 else { return nil }
        if components[1].hasSuffix(".git") {
            components[1].removeLast(4)
        }
        return GitHubRepository(nameWithOwner: components.joined(separator: "/"))
    }

    private var shortcutSettings: some View {
        Form {
            Section {
                ForEach(preferences.shortcutActions) { action in
                    ShortcutRow(action: action, preferences: preferences)
                }
            } header: {
                Text("Commands")
            } footer: {
                Text("Select +, then press a modifier-key combination. Press Escape to cancel.")
            }
        }
        .formStyle(.grouped)
    }

    private var advancedSettings: some View {
        Form {
            Section("Testing") {
                Toggle("Enable testing features", isOn: testingFeaturesEnabled)
            }
            if preferences.testingFeaturesEnabled {
                Section("Closed notch previews") {
                    ForEach(CollapsedIndicatorPreview.allCases) { preview in
                        Stepper(value: collapsedIndicatorPreviewCount(preview), in: 0...preview.maximumPreviewCount) {
                            Text("\(preview.name): \(preferences.collapsedIndicatorPreviewCount(preview))")
                        }
                    }
                }
                Section("Summary previews") {
                    ForEach(SummaryPreview.allCases) { preview in
                        Stepper(value: summaryPreviewCount(preview), in: 0...preview.maximumPreviewCount) {
                            Text("\(preview.name): \(preferences.summaryPreviewCount(preview))")
                        }
                    }
                }
                Section("Priority activities") {
                    Button("Show charging activity") { preferences.triggerTestingSystemActivity(.charging) }
                        .disabled(!preferences.showChargingActivity)
                    Button("Show volume activity") { preferences.triggerTestingSystemActivity(.volume) }
                        .disabled(!preferences.showVolumeActivity)
                    Button("Show brightness activity") { preferences.triggerTestingSystemActivity(.brightness) }
                        .disabled(!preferences.showBrightnessActivity)
                    Button("Show Bluetooth headphones activity") {
                        preferences.triggerTestingSystemActivity(.bluetoothHeadphones)
                    }
                    .disabled(!preferences.showBluetoothHeadphonesActivity)
                }
                Section("Other previews") {
                    if updateModel.isTestingReleaseShown {
                        Button("Hide update preview") {
                            updateModel.hideTestingAvailableRelease()
                        }
                    } else {
                        Button("Show update available") {
                            updateModel.showTestingAvailableRelease()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func numberedLabel(_ number: Int, _ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Label(title, systemImage: symbol)
        }
        .padding(.vertical, 3)
    }

    private func moveCollapsedIndicatorPriority(at index: Int, direction: Int) {
        let destination = direction < 0 ? index - 1 : index + 2
        guard destination >= 0, destination <= preferences.collapsedIndicatorPriorityOrder.count else { return }
        preferences.moveCollapsedIndicatorPriorities(from: IndexSet(integer: index), to: destination)
    }

    private func movePage(at index: Int, direction: Int) {
        let destination = direction < 0 ? index - 1 : index + 2
        guard destination >= 0, destination <= preferences.pageOrder.count else { return }
        preferences.movePages(from: IndexSet(integer: index), to: destination)
    }

    private func moveSummaryPriority(at index: Int, direction: Int) {
        let destination = direction < 0 ? index - 1 : index + 2
        guard destination >= 0, destination <= preferences.summaryPriorityOrder.count else { return }
        preferences.moveSummaryPriorities(from: IndexSet(integer: index), to: destination)
    }

    private func reorderButtons(
        index: Int,
        count: Int,
        itemName: String,
        move: @escaping (Int, Int) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                move(index, -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .accessibilityLabel("Move \(itemName) up")

            Button {
                move(index, 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == count - 1)
            .accessibilityLabel("Move \(itemName) down")
        }
        .controlSize(.small)
    }

    private var showInDock: Binding<Bool> {
        Binding(get: { !preferences.hideFromDock }, set: { preferences.hideFromDock = !$0 })
    }

    private var showInMenuBar: Binding<Bool> {
        Binding(get: { !preferences.hideFromMenuBar }, set: { preferences.hideFromMenuBar = !$0 })
    }

    private var calendarReminderLeadTimeMinutes: Binding<Int> {
        Binding(
            get: { preferences.calendarReminderLeadTimeMinutes },
            set: { preferences.setCalendarReminderLeadTimeMinutes($0) }
        )
    }

    private var transientSystemActivityDurationSeconds: Binding<Int> {
        Binding(
            get: { preferences.transientSystemActivityDurationSeconds },
            set: { preferences.setTransientSystemActivityDurationSeconds($0) }
        )
    }

    private var showChargingActivity: Binding<Bool> {
        Binding(
            get: { preferences.showChargingActivity },
            set: { preferences.setShowChargingActivity($0) }
        )
    }

    private var showVolumeActivity: Binding<Bool> {
        Binding(
            get: { preferences.showVolumeActivity },
            set: { preferences.setShowVolumeActivity($0) }
        )
    }

    private var showBrightnessActivity: Binding<Bool> {
        Binding(
            get: { preferences.showBrightnessActivity },
            set: { preferences.setShowBrightnessActivity($0) }
        )
    }

    private var showBluetoothHeadphonesActivity: Binding<Bool> {
        Binding(
            get: { preferences.showBluetoothHeadphonesActivity },
            set: { preferences.setShowBluetoothHeadphonesActivity($0) }
        )
    }

    private var showDownloads: Binding<Bool> {
        Binding(
            get: { preferences.showDownloads },
            set: { preferences.setShowDownloads($0) }
        )
    }

    private var showHomebrewDownloads: Binding<Bool> {
        Binding(
            get: { preferences.showHomebrewDownloads },
            set: { preferences.setShowHomebrewDownloads($0) }
        )
    }

    private var defaultDownloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/Downloads", isDirectory: true)
    }

    private func chooseDownloadsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = preferences.downloadsDirectoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.setDownloadsDirectoryURL(url)
    }

    private var preferredDisplayID: Binding<String> {
        Binding(
            get: { preferences.preferredDisplayID ?? "pointer" },
            set: { preferences.setPreferredDisplayID($0 == "pointer" ? nil : $0) }
        )
    }

    private var externalNotchStyle: Binding<String> {
        Binding(
            get: { preferences.externalNotchStyle.rawValue },
            set: { preferences.setExternalNotchStyle(ExternalNotchStyle(rawValue: $0) ?? .capsule) }
        )
    }

    private func collapsedIndicatorPreviewCount(_ preview: CollapsedIndicatorPreview) -> Binding<Int> {
        Binding(
            get: { preferences.collapsedIndicatorPreviewCount(preview) },
            set: { preferences.setCollapsedIndicatorPreviewCount($0, for: preview) }
        )
    }

    private func summaryPreviewCount(_ preview: SummaryPreview) -> Binding<Int> {
        Binding(
            get: { preferences.summaryPreviewCount(preview) },
            set: { preferences.setSummaryPreviewCount($0, for: preview) }
        )
    }

    private var collapsedIndicatorMaximumPerSide: Binding<Int> {
        Binding(
            get: { preferences.collapsedIndicatorMaximumPerSide },
            set: { preferences.setCollapsedIndicatorMaximumPerSide($0) }
        )
    }

    private func collapsedIndicatorCategory(_ category: CollapsedNotchIndicatorCategory) -> Binding<Bool> {
        Binding(
            get: { preferences.isCollapsedIndicatorCategoryEnabled(category) },
            set: { preferences.setCollapsedIndicatorCategory(category, isVisible: $0) }
        )
    }

    private func collapsedIndicatorColor(_ category: CollapsedNotchIndicatorCategory) -> Binding<Color> {
        Binding(
            get: { preferences.customCollapsedIndicatorColor(for: category) ?? category.defaultColor },
            set: { preferences.setCollapsedIndicatorColor($0, for: category) }
        )
    }

    private var testingFeaturesEnabled: Binding<Bool> {
        Binding(
            get: { preferences.testingFeaturesEnabled },
            set: { preferences.setTestingFeaturesEnabled($0) }
        )
    }

    private var dynamicPagesEnabled: Binding<Bool> {
        Binding(
            get: { preferences.dynamicPagesEnabled },
            set: { preferences.setDynamicPagesEnabled($0) }
        )
    }

    private var hasEnabledSystemActivity: Bool {
        preferences.showChargingActivity
            || preferences.showVolumeActivity
            || preferences.showBrightnessActivity
            || preferences.showBluetoothHeadphonesActivity
    }

    private func pageVisibility(_ page: NotchPage) -> Binding<Bool> {
        Binding(
            get: { preferences.isVisible(page) },
            set: { preferences.setVisible(page, isVisible: $0) }
        )
    }

    private func canHide(_ page: NotchPage) -> Bool {
        !preferences.isVisible(page) || preferences.visiblePages.count > 1
    }

    private func indicatorCategory(for page: NotchPage) -> CollapsedNotchIndicatorCategory? {
        CollapsedNotchIndicatorCategory.allCases.first { $0.ownerPage == page }
    }

    private func indicatorColorDescription(for category: CollapsedNotchIndicatorCategory) -> String {
        switch category {
        case .codingAgents, .githubActions:
            "Failures remain red and completed activity remains green."
        default:
            "This color is used while the activity is active."
        }
    }
}

private extension SettingsDestination {
    var title: String {
        switch self {
        case .general: "General"
        case .notch: "Notch"
        case .pages: "Pages"
        case let .page(page): page.name
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    let title: String
    let isSidebarVisible: Bool
    let toggleSidebar: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = SettingsWindowConfigurationView()
        view.update(
            title: title,
            isSidebarVisible: isSidebarVisible,
            toggleSidebar: toggleSidebar
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? SettingsWindowConfigurationView else { return }
        view.update(
            title: title,
            isSidebarVisible: isSidebarVisible,
            toggleSidebar: toggleSidebar
        )
    }
}

private final class SettingsWindowConfigurationView: NSView {
    private var title = ""
    private var isSidebarVisible = true
    private var toggleSidebar: () -> Void = {}
    private weak var titlebarControls: SettingsTitlebarControlsView?
    private var mouseMonitor: Any?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMouseMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            removeMouseMonitor()
            return
        }
        window.styleMask.formUnion([.fullSizeContentView, .miniaturizable, .resizable])
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        updateTitlebarControls()
        installMouseMonitor()
    }

    func update(title: String, isSidebarVisible: Bool, toggleSidebar: @escaping () -> Void) {
        self.title = title
        self.isSidebarVisible = isSidebarVisible
        self.toggleSidebar = toggleSidebar
        updateTitlebarControls()
    }

    private func updateTitlebarControls() {
        guard
            let closeButton = window?.standardWindowButton(.closeButton),
            let windowFrameView = window?.contentView?.superview
        else { return }
        let controls = titlebarControls ?? makeTitlebarControls(in: windowFrameView)
        controls.controlCenterY = (closeButton.bounds.height / 2) + 16
        controls.update(
            title: title,
            isSidebarVisible: isSidebarVisible,
            toggleSidebar: toggleSidebar
        )
    }

    private func makeTitlebarControls(in windowFrameView: NSView) -> SettingsTitlebarControlsView {
        let controls = SettingsTitlebarControlsView(frame: windowFrameView.bounds)
        controls.autoresizingMask = [.width, .height]
        windowFrameView.addSubview(controls, positioned: .above, relativeTo: nil)
        titlebarControls = controls
        return controls
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard
                let self,
                event.window === window,
                let titlebarControls,
                titlebarControls.containsSidebarButton(windowPoint: event.locationInWindow)
            else { return event }

            titlebarControls.performToggleSidebar()
            return nil
        }
    }

    private func removeMouseMonitor() {
        guard let mouseMonitor else { return }
        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }
}

private final class SettingsTitlebarControlsView: NSView {
    private let sidebarButton: SettingsSidebarButton
    private let titleLabel = NSTextField(labelWithString: "")
    private let separator = NSBox()
    private var isSidebarVisible = true
    private var toggleSidebar: () -> Void = {}
    var controlCenterY: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        let image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil) ?? NSImage()
        sidebarButton = SettingsSidebarButton(image: image, target: nil, action: nil)
        super.init(frame: frameRect)

        sidebarButton.isBordered = false
        sidebarButton.imageScaling = .scaleProportionallyDown
        sidebarButton.sendAction(on: .leftMouseDown)
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebarAction)
        sidebarButton.setAccessibilityLabel("Hide sidebar")
        addSubview(sidebarButton)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        separator.boxType = .separator
        addSubview(separator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(title: String, isSidebarVisible: Bool, toggleSidebar: @escaping () -> Void) {
        titleLabel.stringValue = title
        self.isSidebarVisible = isSidebarVisible
        self.toggleSidebar = toggleSidebar
        let action = isSidebarVisible ? "Hide sidebar" : "Show sidebar"
        sidebarButton.toolTip = action
        sidebarButton.setAccessibilityLabel(action)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let buttonSize = NSSize(width: 20, height: 20)
        sidebarButton.frame = NSRect(
            x: isSidebarVisible ? settingsSidebarWidth - 34 : 78,
            y: controlCenterY - (buttonSize.height / 2),
            width: buttonSize.width,
            height: buttonSize.height
        )

        let titleX: CGFloat = isSidebarVisible ? settingsSidebarWidth + 20 : 112
        let labelHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(
            x: titleX,
            y: controlCenterY - (labelHeight / 2),
            width: max(0, bounds.width - titleX - 20),
            height: labelHeight
        )

        separator.isHidden = !isSidebarVisible
        separator.frame = NSRect(x: settingsSidebarWidth - 1, y: 0, width: 1, height: bounds.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        sidebarButton.frame.contains(point) ? sidebarButton : nil
    }

    func containsSidebarButton(windowPoint: NSPoint) -> Bool {
        sidebarButton.frame.contains(convert(windowPoint, from: nil))
    }

    func performToggleSidebar() {
        toggleSidebar()
    }

    @objc private func toggleSidebarAction() {
        performToggleSidebar()
    }
}

private final class SettingsSidebarButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var preferences: NotchPreferences
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 10) {
            Text(preferences.shortcutTitle(for: action))
            Spacer()
            if isRecording {
                ShortcutRecorder(
                    onRecord: {
                        preferences.setShortcut($0, for: action)
                        isRecording = false
                    },
                    onCancel: { isRecording = false }
                )
            } else {
                Text(preferences.shortcut(for: action).displayName)
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .frame(minWidth: 58)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("Current shortcut: \(preferences.shortcut(for: action).displayName)")
            }
            Button { isRecording = true } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Customize this command")
            .accessibilityLabel("Customize \(preferences.shortcutTitle(for: action))")
        }
        .padding(.vertical, 5)
    }
}
