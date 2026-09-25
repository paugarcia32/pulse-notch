import AppKit
import PulseNotchCore
import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject var model: AIAgentFeatureModel
    @ObservedObject var permissions: ComputerUsePermissions
    @State private var secrets: [CredentialAccount: String] = [:]
    @State private var replacing: Set<CredentialAccount> = []
    @State private var manualModelID = ""
    @State private var confirmClear = false

    var body: some View {
        Form {
            decisionSection
            languageSection
            localComponentsSection
            computerUseSection
            privacySection
            connectionSection
            historySection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            permissions.refresh()
            Task { await model.refreshComponents() }
        }
    }

    // MARK: Providers

    private var decisionSection: some View {
        Section {
            Picker("Provider", selection: $model.settings.decisionKind) {
                ForEach(AIAgentSettings.DecisionKind.allCases) { Text($0.title).tag($0) }
            }
            switch model.settings.decisionKind {
            case .jev:
                TextField("Model", text: $model.settings.jevModel)
                credentialRow(.typeSafe)
            case .managedLaya:
                Text("Laya runs on this Mac in an isolated Python runtime. It has no desktop-control permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .layaEndpoint:
                TextField("Service URL", text: $model.settings.layaEndpointURL)
                TextField("Model", text: $model.settings.layaEndpointModel)
                credentialRow(.layaEndpoint, optional: true)
            }
        } header: {
            Text("Decisions")
        } footer: {
            Text("Structured choices, risk checks, and outcome verification. This provider never writes chat replies.")
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Provider", selection: $model.settings.languageKind) {
                ForEach(AIAgentSettings.LanguageKind.allCases) { Text($0.title).tag($0) }
            }
            switch model.settings.languageKind {
            case .openRouter:
                credentialRow(.openRouter)
                modelPicker(selection: $model.settings.openRouterModel)
            case .managedLocal:
                Picker("Model", selection: $model.settings.localModelID) {
                    ForEach(model.manifest?.languageModels ?? []) { Text($0.name).tag($0.id) }
                    ForEach(model.importedModels) { Text("\($0.name) (imported)").tag($0.id) }
                }
                Text("Pulse Notch never switches models on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .localEndpoint:
                TextField("Server URL", text: $model.settings.localEndpointURL)
                credentialRow(.localLanguageEndpoint, optional: true)
                modelPicker(selection: $model.settings.localEndpointModel)
            }
            capabilityRow
        } header: {
            Text("Conversation and planning")
        }
    }

    private func modelPicker(selection: Binding<String>) -> some View {
        Group {
            HStack {
                Picker("Model", selection: selection) {
                    if selection.wrappedValue.isEmpty { Text("Choose a model").tag("") }
                    ForEach(model.catalog) { info in
                        Text(Self.describe(info)).tag(info.id)
                    }
                }
                Button {
                    Task { await model.refreshCatalog() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh the model catalog")
            }
            if let status = model.catalogStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Manual model ID", text: $manualModelID)
                Button("Use") {
                    selection.wrappedValue = manualModelID.trimmingCharacters(in: .whitespaces)
                    manualModelID = ""
                }
                .disabled(manualModelID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    static func describe(_ info: ModelInfo) -> String {
        var parts = [info.name]
        var capabilities: [String] = []
        if info.capabilities.supportsTools { capabilities.append("tools") }
        if info.capabilities.supportsVision { capabilities.append("vision") }
        if let context = info.capabilities.contextLength { capabilities.append("\(context / 1000)k") }
        if !capabilities.isEmpty { parts.append(capabilities.joined(separator: ", ")) }
        if let prompt = info.pricing?.prompt, let completion = info.pricing?.completion {
            let perMillion = { (value: Decimal) in (value * 1_000_000).formatted(.currency(code: "USD").precision(.fractionLength(0...2))) }
            parts.append("\(perMillion(prompt))/\(perMillion(completion)) per 1M")
        }
        return parts.joined(separator: " · ")
    }

    private var capabilityRow: some View {
        let report = model.settings.capabilityReport
        return Group {
            if let report {
                Label(
                    report.toolCallsVerified
                        ? (report.visionVerified ? "Tool calls and screenshots verified" : "Tool calls verified; screenshots unavailable")
                        : "Not ready for computer use",
                    systemImage: report.toolCallsVerified ? "checkmark.seal" : "xmark.seal"
                )
                .font(.caption)
            } else {
                Label("Run Test connection to verify tool calls and vision", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func credentialRow(_ account: CredentialAccount, optional: Bool = false) -> some View {
        HStack {
            if model.hasCredential(account) && !replacing.contains(account) {
                Label("\(account.displayName) saved in Keychain", systemImage: "key.fill")
                    .font(.caption)
                Spacer()
                Button("Replace") { replacing.insert(account) }
                Button("Disconnect", role: .destructive) { model.removeCredential(account) }
            } else {
                SecureField(optional ? "\(account.displayName) (optional)" : account.displayName, text: Binding(
                    get: { secrets[account] ?? "" },
                    set: { secrets[account] = $0 }
                ))
                // The saved key is replaced only once the new one is stored.
                Button("Save") {
                    model.setCredential(secrets[account] ?? "", for: account)
                    secrets[account] = nil
                    replacing.remove(account)
                }
                .disabled((secrets[account] ?? "").isEmpty)
                if replacing.contains(account) {
                    Button("Cancel") {
                        secrets[account] = nil
                        replacing.remove(account)
                    }
                }
            }
        }
    }

    // MARK: Local components

    private var localComponentsSection: some View {
        Section {
            if let manifest = model.manifest {
                if model.settings.decisionKind == .managedLaya {
                    ForEach(manifest.decisionModels) { component in
                        componentRow(id: component.id, name: component.name, size: component.downloadSize, license: component.license, note: "Includes the Python runtime (\(manifest.runtime("python")?.version ?? "")).")
                    }
                }
                if model.settings.languageKind == .managedLocal {
                    if let runtime = manifest.runtime("llama.cpp") {
                        componentRow(id: runtime.id, name: runtime.name, size: runtime.archive.size, license: runtime.license, note: "Version \(runtime.version)")
                    }
                    ForEach(manifest.languageModels) { component in
                        componentRow(id: component.id, name: component.name, size: component.downloadSize, license: component.license, note: component.minimumMemoryGB.map { "Needs \($0) GB of memory or more." })
                    }
                    Button("Import GGUF model…", action: importModel)
                }
                if model.settings.decisionKind != .managedLaya && model.settings.languageKind != .managedLocal {
                    Text("Choose a managed provider above to install local components.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Local components")
        } footer: {
            Text("Nothing downloads until you choose Install. Installed components work offline.")
        }
    }

    private func componentRow(id: String, name: String, size: Int64, license: String, note: String?) -> some View {
        let state = model.componentStates[id] ?? .notInstalled
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.callout)
                    Text("\(RuntimeError.bytes(size)) · \(license)" + (note.map { " · \($0)" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                switch state {
                case .installed:
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Button("Remove", role: .destructive) { Task { await model.removeComponent(id) } }
                case .downloading, .verifying, .installing:
                    Button("Cancel") { model.cancelInstall(id) }
                case .notInstalled, .failed:
                    Button(state == .notInstalled ? "Install" : "Retry") { model.install(id) }
                }
            }
            switch state {
            case .downloading(let received, let total):
                ProgressView(value: Double(received), total: Double(max(total, 1))) {
                    Text("\(RuntimeError.bytes(received)) of \(RuntimeError.bytes(total))").font(.caption2)
                }
            case .verifying:
                ProgressView { Text("Verifying checksum…").font(.caption2) }
            case .installing(let step):
                ProgressView { Text(step).font(.caption2) }
            case .failed(let message):
                Text(message).font(.caption2).foregroundStyle(.red)
            case .notInstalled, .installed:
                EmptyView()
            }
        }
    }

    private func importModel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose a GGUF model and, optionally, its vision projector (mmproj)."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let projector = panel.urls.first { $0.lastPathComponent.lowercased().contains("mmproj") }
        guard let modelURL = panel.urls.first(where: { $0 != projector }) else { return }
        Task { await model.importModel(from: modelURL, projector: projector) }
    }

    // MARK: Computer use

    private var computerUseSection: some View {
        Section {
            Toggle("Allow computer use", isOn: Binding(
                get: { model.settings.computerUseEnabled },
                set: { enabled in
                    model.settings.computerUseEnabled = enabled
                    if enabled {
                        permissions.requestAccessibility()
                        permissions.startMonitoring()
                    } else {
                        permissions.stopMonitoring()
                    }
                }
            ))
            if model.settings.computerUseEnabled && model.settings.decisionKind != .jev {
                Label(
                    "JEV is recommended for computer use. In published community tests the official Laya checkpoints chose the right on-screen control far less reliably than JEV without fine-tuning.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            if model.settings.computerUseEnabled {
                permissionRow("Accessibility", granted: permissions.accessibilityGranted, request: permissions.requestAccessibility, open: permissions.openAccessibilitySettings)
                permissionRow("Screen Recording (optional, for screenshots)", granted: permissions.screenRecordingGranted, request: permissions.requestScreenRecording, open: permissions.openScreenRecordingSettings)
                Picker("Mode", selection: $model.settings.executionMode) {
                    Text("Autonomous").tag(ExecutionMode.autonomous)
                    Text("Supervised (approve each action)").tag(ExecutionMode.supervised)
                }
                TextField("Never control (bundle IDs, comma separated)", text: bundleList(\.deniedBundleIDs))
                TextField("Only control (bundle IDs, empty for any)", text: bundleList(\.allowedBundleIDs))
                LimitsEditor(limits: $model.settings.limits)
            }
        } header: {
            Text("Computer use")
        } footer: {
            Text("One desktop task runs at a time; others wait in a queue. Typing in the agent composer pauses desktop input. The emergency-stop shortcut stops every run.")
        }
    }

    private func permissionRow(_ title: String, granted: Bool, request: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.shield.fill" : "exclamationmark.shield")
                .foregroundStyle(granted ? .green : .orange)
            Spacer()
            if !granted {
                Button("Request", action: request)
                Button("Open Settings", action: open)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? "Granted" : "Not granted")
    }

    private func bundleList(_ keyPath: WritableKeyPath<AIAgentSettings, [String]>) -> Binding<String> {
        Binding(
            get: { model.settings[keyPath: keyPath].joined(separator: ", ") },
            set: { text in
                model.settings[keyPath: keyPath] = text
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    // MARK: Privacy, testing, history

    private var privacySection: some View {
        Section("Privacy") {
            Text(privacyText)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if model.settings.usesHostedProvider {
                Toggle("I understand what is sent to hosted providers", isOn: $model.settings.hostedDataDisclosureAccepted)
            }
        }
    }

    private var privacyText: String {
        var lines: [String] = []
        if !model.settings.decisionSelection.isLocal {
            lines.append("• Decisions (\(model.settings.decisionKind.title)): for each step, your instruction, the step, and the names of the relevant on-screen controls are sent so the decision model can choose and verify actions. Screenshots are never sent to the decision provider.")
        }
        if !model.settings.languageSelection.isLocal {
            lines.append("• Language model (\(model.settings.languageKind.title)): the conversation, a summary of the screen after each step, and — only for models that pass the vision check — a screenshot after each step.")
        }
        if lines.isEmpty {
            lines.append("Both providers run on this Mac. Browsing or using online apps during a task can still reach the network.")
        }
        lines.append("Credentials and secure fields are never sent or logged. Screenshots are kept in memory only. Transcripts and action summaries are stored on this Mac for \(model.settings.retentionDays) days.")
        return lines.joined(separator: "\n")
    }

    private var connectionSection: some View {
        Section {
            HStack {
                Button("Test connection") { Task { await model.testConnection() } }
                    .disabled(model.isTestingConnection)
                if model.isTestingConnection { ProgressView().controlSize(.small) }
            }
            if let status = model.connectionStatus {
                Text(status)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } footer: {
            Text("Sends a small decision request and a real tool call. Models that also identify a test image are allowed to use screenshots.")
        }
    }

    private var historySection: some View {
        Section("History") {
            Stepper(value: $model.settings.retentionDays, in: 1...365) {
                Text("Keep transcripts for \(model.settings.retentionDays) days")
            }
            Button("Clear history…", role: .destructive) { confirmClear = true }
                .confirmationDialog("Clear all AI Agent history?", isPresented: $confirmClear) {
                    Button("Clear history", role: .destructive) { Task { await model.clearHistory() } }
                } message: {
                    Text("Conversations and run history are deleted. Goals, routines, and downloaded models are kept.")
                }
        }
    }
}
