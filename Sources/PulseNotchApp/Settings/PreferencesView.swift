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

struct PreferencesView: View {
    @ObservedObject var preferences: NotchPreferences
    @ObservedObject var updateModel: UpdateFeatureModel
    let displays: [NotchDisplayOption]
    @State private var selection = SettingsDestination.general
    @State private var gitHubRepositoryName = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: SettingsDestination.general) {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: SettingsDestination.notch) {
                    Label("Notch", systemImage: "macbook")
                }

                Section("Pages") {
                    NavigationLink(value: SettingsDestination.pages) {
                        Label("Overview", systemImage: "rectangle.3.group")
                    }
                    ForEach(preferences.pageOrder) { page in
                        NavigationLink(value: SettingsDestination.page(page)) {
                            Label(page.name, systemImage: page.symbolName)
                        }
                    }
                }

                Section {
                    NavigationLink(value: SettingsDestination.shortcuts) {
                        Label("Shortcuts", systemImage: "command")
                    }
                    NavigationLink(value: SettingsDestination.advanced) {
                        Label("Advanced", systemImage: "gearshape.2")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 480, idealHeight: 540)
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
        .navigationTitle("General")
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
        List {
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
                    numberedLabel(index + 1, category.name, symbol: category.symbolName)
                }
                .onMove(perform: preferences.moveCollapsedIndicatorPriorities)
            } header: {
                Text("Activity priority")
            } footer: {
                Text("Drag to decide which activities remain visible when space is limited.")
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
        .listStyle(.inset)
        .navigationTitle("Notch")
    }

    private var pagesOverview: some View {
        List {
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
                .onMove(perform: preferences.movePages)
            } header: {
                Text("Page order")
            } footer: {
                Text("Drag to reorder. Select a page to configure its visibility and activity.")
            }
        }
        .listStyle(.inset)
        .navigationTitle("Pages")
    }

    private func pageSettings(_ page: NotchPage) -> some View {
        List {
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
                        numberedLabel(index + 1, priority.name, symbol: priority.symbolName)
                    }
                    .onMove(perform: preferences.moveSummaryPriorities)
                } header: {
                    Text("Content priority")
                } footer: {
                    Text("The first priority with relevant activity fills the Summary page.")
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
        .listStyle(.inset)
        .navigationTitle(page.name)
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
                }
            }
            .disabled(!preferences.showDownloads)
            if preferences.downloadsDirectoryURL != defaultDownloadsDirectory {
                Button("Use Downloads folder") {
                    preferences.setDownloadsDirectoryURL(defaultDownloadsDirectory)
                }
                .disabled(!preferences.showDownloads)
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
                TextField("owner/repository", text: $gitHubRepositoryName)
                    .onSubmit(addGitHubRepository)
                Button("Add", action: addGitHubRepository)
                    .disabled(!canAddGitHubRepository)
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

    private var canAddGitHubRepository: Bool {
        guard let repository = GitHubRepository(nameWithOwner: gitHubRepositoryName) else { return false }
        return !preferences.monitoredGitHubRepositories.contains { $0.id == repository.id }
    }

    private func addGitHubRepository() {
        guard preferences.addMonitoredGitHubRepository(named: gitHubRepositoryName) else { return }
        gitHubRepositoryName = ""
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
        .navigationTitle("Shortcuts")
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
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
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
