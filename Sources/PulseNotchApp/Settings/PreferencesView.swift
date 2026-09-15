import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: NotchPreferences
    let displays: [NotchDisplayOption]

    var body: some View {
        TabView {
            Form {
                Section("Startup") {
                    Toggle("Open at Login", isOn: $preferences.openAtLogin)
                    if let startupError = preferences.startupError {
                        Text(startupError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Presence") {
                    Toggle("Show in Dock", isOn: showInDock)
                    Toggle("Show in Menu Bar", isOn: showInMenuBar)
                }

                Section("Display") {
                    Picker("Show Pulse Notch on", selection: preferredDisplayID) {
                        Text("Display under pointer").tag("pointer")
                        ForEach(displays) { display in
                            Text(display.name).tag(display.id)
                        }
                    }

                    Picker("External display style", selection: externalNotchStyle) {
                        Text(ExternalNotchStyle.capsule.name).tag(ExternalNotchStyle.capsule.rawValue)
                        Text(ExternalNotchStyle.rectangle.name).tag(ExternalNotchStyle.rectangle.rawValue)
                    }
                    Text("This setting only affects displays without a physical notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Calendar") {
                    Stepper(value: calendarReminderLeadTimeMinutes, in: 1...60) {
                        Text("Show upcoming events \(preferences.calendarReminderLeadTimeMinutes) minutes before they start")
                    }
                }

                Section("Closed notch") {
                    Stepper(value: collapsedIndicatorMaximumPerSide, in: 1...5) {
                        Text("Maximum items per side: \(preferences.collapsedIndicatorMaximumPerSide)")
                    }
                    Text("More than 3 items per side is not recommended.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(CollapsedNotchIndicatorCategory.allCases) { category in
                        Toggle(category.name, isOn: collapsedIndicatorCategory(category))
                    }
                }

                Section("Temporary system activities") {
                    Toggle("Show charging activity", isOn: showChargingActivity)
                    Toggle("Show volume activity", isOn: showVolumeActivity)
                    Toggle("Show brightness activity", isOn: showBrightnessActivity)
                    Stepper(value: transientSystemActivityDurationSeconds, in: 1...10) {
                        Text("Show for \(preferences.transientSystemActivityDurationSeconds) seconds")
                    }
                    .disabled(!preferences.showChargingActivity)
                }

                Section("Testing") {
                    Toggle("Enable testing features", isOn: testingFeaturesEnabled)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }

            Form {
                Section {
                    ForEach(preferences.shortcutActions) { action in
                        ShortcutRow(action: action, preferences: preferences)
                    }
                } header: {
                    Text("Commands")
                } footer: {
                    Text("Select +, then press a modifier-key combination. Press Escape to cancel.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Shortcuts", systemImage: "command") }

            List {
                Section {
                    ForEach(Array(preferences.pageOrder.enumerated()), id: \.element.id) { index, page in
                        PagePreferenceRow(
                            page: page,
                            position: index + 1,
                            preferences: preferences
                        )
                    }
                    .onMove(perform: preferences.movePages)
                } header: {
                    Text("Notch Pages")
                } footer: {
                    Text("Drag a row to change the order. Turn off a page to hide it from the notch.")
                }
            }
            .listStyle(.inset)
            .tabItem { Label("Pages", systemImage: "rectangle.3.group") }

            if preferences.testingFeaturesEnabled {
                Form {
                    Section("Closed notch previews") {
                        Text("Choose sample indicators, then trigger a priority activity to verify that it replaces them temporarily.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(CollapsedIndicatorPreview.allCases) { preview in
                            Stepper(value: collapsedIndicatorPreviewCount(preview), in: 0...preview.maximumPreviewCount) {
                                Text("\(preview.name): \(preferences.collapsedIndicatorPreviewCount(preview))")
                            }
                        }
                    }

                    Section("Priority activities") {
                        Button("Show charging activity") {
                            preferences.triggerTestingSystemActivity(.charging)
                        }
                        .disabled(!preferences.showChargingActivity)
                        .accessibilityHint("Temporarily replaces the closed notch previews")
                        Button("Show volume activity") {
                            preferences.triggerTestingSystemActivity(.volume)
                        }
                        .disabled(!preferences.showVolumeActivity)
                        Button("Show brightness activity") {
                            preferences.triggerTestingSystemActivity(.brightness)
                        }
                        .disabled(!preferences.showBrightnessActivity)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("Testing", systemImage: "testtube.2") }
            }
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 340, idealHeight: 380)
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
            get: { preferences.isCollapsedIndicatorCategoryVisible(category) },
            set: { preferences.setCollapsedIndicatorCategory(category, isVisible: $0) }
        )
    }

    private var testingFeaturesEnabled: Binding<Bool> {
        Binding(
            get: { preferences.testingFeaturesEnabled },
            set: { preferences.setTestingFeaturesEnabled($0) }
        )
    }

}

private struct PagePreferenceRow: View {
    let page: NotchPage
    let position: Int
    @ObservedObject var preferences: NotchPreferences

    var body: some View {
        HStack(spacing: 10) {
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Label(page.name, systemImage: page.symbolName)
                .foregroundStyle(preferences.isVisible(page) ? .primary : .secondary)
            Spacer()
            Toggle("Show \(page.name)", isOn: Binding(
                get: { preferences.isVisible(page) },
                set: { preferences.setVisible(page, isVisible: $0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 3)
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
