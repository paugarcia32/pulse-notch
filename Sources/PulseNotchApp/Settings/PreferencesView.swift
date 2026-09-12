import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: NotchPreferences

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

                Section("Calendar") {
                    Stepper(value: calendarReminderLeadTimeMinutes, in: 1...60) {
                        Text("Show upcoming events \(preferences.calendarReminderLeadTimeMinutes) minutes before they start")
                    }
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
