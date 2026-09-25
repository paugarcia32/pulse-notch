import Foundation
import PulseNotchCore

enum AgentIndicatorState: String, Hashable, Sendable, CaseIterable {
    case running
    case paused
    case needsInput
    case completed
    case failed

    var label: String {
        switch self {
        case .running: "AI Agent running"
        case .paused: "AI Agent paused"
        case .needsInput: "AI Agent needs input"
        case .completed: "AI Agent finished"
        case .failed: "AI Agent failed"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "sparkles"
        case .paused: "pause.fill"
        case .needsInput: "questionmark.bubble.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

struct ChatEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let role: ChatRole
    let text: String
    let runID: UUID?
    let createdAt: Date
}

/// A run that is executing, paused, or waiting for input in this session.
struct LiveRun: Identifiable {
    var run: AgentRun
    let control: RunControl
    var task: Task<Void, Never>?
    /// The transcript to continue from after a pause or a request for input.
    var resumeMessages: [ChatMessage] = []
    var streamingText = ""
    let completionCriteria: String?
    let limits: RunLimits

    var id: UUID { run.id }
    var isExecuting: Bool { task != nil }
}

/// Bridges the AI Agent's actors and stores to SwiftUI. It owns every run task and
/// the routine scheduler, and it outlives the collapsed panel, so drafts survive.
@MainActor
final class AIAgentFeatureModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case chat
        case goals
        case routines
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chat: "Chat"
            case .goals: "Goals"
            case .routines: "Routines"
            case .settings: "Settings"
            }
        }

        var symbolName: String {
            switch self {
            case .chat: "bubble.left.and.bubble.right"
            case .goals: "target"
            case .routines: "calendar.badge.clock"
            case .settings: "gearshape"
            }
        }
    }

    @Published private(set) var isEnabled = false
    @Published var settings: AIAgentSettings { didSet { if settings != oldValue { settingsStore.save(settings) } } }
    @Published var selectedTab: Tab = .chat
    @Published var draft = ""
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var selectedConversationID: UUID?
    @Published private(set) var chatEntries: [ChatEntry] = []
    @Published private(set) var goals: [Goal] = []
    @Published private(set) var routines: [Routine] = []
    @Published private(set) var liveRuns: [UUID: LiveRun] = [:]
    @Published private(set) var recentRuns: [AgentRun] = []
    @Published private(set) var missedOccurrences: [MissedOccurrence] = []
    @Published private(set) var componentStates: [String: ComponentState] = [:]
    @Published private(set) var importedModels: [ImportedModel] = []
    @Published private(set) var catalog: [ModelInfo] = []
    @Published private(set) var catalogStatus: String?
    @Published private(set) var connectionStatus: String?
    @Published private(set) var isTestingConnection = false
    @Published private(set) var storedCredentials: Set<CredentialAccount> = []
    @Published private(set) var lastError: String?
    @Published private(set) var unacknowledgedOutcome: AgentIndicatorState?

    let manifest: RuntimeManifest?
    private var store: (any AgentStore)?
    /// Opens the database on first enable, so a disabled agent creates no files.
    private let makeStore: (() throws -> any AgentStore)?
    private let credentials: any CredentialStore
    private let runtimes: LocalRuntimeManager?
    private let factory: AgentProviderFactory?
    private let executor: (any ComputerUseExecutor)?
    private let availability: any DesktopAvailability
    private let settingsStore: AIAgentSettingsStore
    private let clock: any AgentClock
    private let scheduler: RoutineScheduler
    private let lease = DesktopLease()
    private let onComposerFocusChange: (Bool) -> Void
    private var schedulerTask: Task<Void, Never>?
    private var componentStateTask: Task<Void, Never>?
    private var installTasks: [String: Task<Void, Never>] = [:]
    private var lastPurge: Date?

    init(
        store: (any AgentStore)? = nil,
        makeStore: (() throws -> any AgentStore)? = nil,
        credentials: any CredentialStore,
        runtimes: LocalRuntimeManager?,
        componentStates: AsyncStream<(String, ComponentState)>?,
        factory: AgentProviderFactory?,
        executor: (any ComputerUseExecutor)?,
        availability: any DesktopAvailability,
        settingsStore: AIAgentSettingsStore,
        clock: any AgentClock = SystemAgentClock(),
        scheduler: RoutineScheduler = RoutineScheduler(),
        storeError: String? = nil,
        onComposerFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.makeStore = makeStore
        self.credentials = credentials
        self.runtimes = runtimes
        self.manifest = runtimes?.manifest
        self.factory = factory
        self.executor = executor
        self.availability = availability
        self.settingsStore = settingsStore
        self.clock = clock
        self.scheduler = scheduler
        self.onComposerFocusChange = onComposerFocusChange
        self.settings = settingsStore.load()
        self.lastError = storeError
        refreshCredentialPresence()
        if let componentStates {
            componentStateTask = Task { [weak self] in
                for await (id, state) in componentStates {
                    self?.componentStates[id] = state
                }
            }
        }
    }

    // MARK: Lifecycle

    /// Starts scheduling and loads history. Disabling cancels every run and stops
    /// managed processes; it keeps history and downloaded models.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            if store == nil, let makeStore {
                do {
                    store = try makeStore()
                } catch {
                    lastError = "The agent database could not be opened: \(error.localizedDescription)"
                }
            }
            await loadAll()
            startScheduler()
        } else {
            schedulerTask?.cancel()
            schedulerTask = nil
            stopAll()
            await factory?.stopManagedRuntimes()
        }
    }

    /// Called when Pulse Notch quits: stops runs and managed runtimes.
    func shutdown() async {
        schedulerTask?.cancel()
        componentStateTask?.cancel()
        installTasks.values.forEach { $0.cancel() }
        stopAll()
        await factory?.stopManagedRuntimes()
    }

    private func loadAll() async {
        guard let store else { return }
        do {
            let interrupted = try await store.markUnfinishedRunsInterrupted(at: clock.now)
            if !interrupted.isEmpty {
                lastError = "\(interrupted.count) run(s) were interrupted when Pulse Notch last quit. Review them before running again."
            }
            try await purgeIfNeeded()
            conversations = try await store.conversations()
            goals = try await store.goals()
            routines = try await store.routines()
            recentRuns = try await store.recentRuns(limit: 50)
            missedOccurrences = try await store.missedOccurrences()
            if selectedConversationID == nil, let latest = conversations.first {
                try await selectConversation(latest.id)
            }
        } catch {
            lastError = "The agent history could not be loaded: \(error.localizedDescription)"
        }
        await refreshComponents()
    }

    private func purgeIfNeeded() async throws {
        guard let store else { return }
        let now = clock.now
        if let lastPurge, now.timeIntervalSince(lastPurge) < 24 * 60 * 60 { return }
        let days = max(1, settings.retentionDays)
        try await store.purgeHistory(olderThan: now.addingTimeInterval(-Double(days) * 24 * 60 * 60))
        lastPurge = now
    }

    // MARK: Indicator

    var indicatorState: AgentIndicatorState? {
        let active = liveRuns.values.map(\.run.status)
        if active.contains(where: { if case .needsInput = $0 { true } else { false } }) { return .needsInput }
        if active.contains(.running) || active.contains(.queued) { return .running }
        if active.contains(where: { if case .paused = $0 { true } else { false } }) { return .paused }
        return unacknowledgedOutcome
    }

    func acknowledgeOutcome() {
        unacknowledgedOutcome = nil
    }

    func setComposerFocused(_ focused: Bool) {
        onComposerFocusChange(focused)
    }

    // MARK: Chat

    var selectedConversationRun: LiveRun? {
        guard let selectedConversationID else { return nil }
        return liveRuns.values.first { $0.run.trigger == .chat(conversationID: selectedConversationID) }
    }

    func newConversation() {
        selectedConversationID = nil
        chatEntries = []
    }

    func selectConversation(_ id: UUID) async throws {
        selectedConversationID = id
        guard let store else { return }
        chatEntries = try await store.messages(in: id).map {
            ChatEntry(id: $0.id, role: $0.role, text: $0.text, runID: $0.runID, createdAt: $0.createdAt)
        }
    }

    func deleteConversation(_ id: UUID) async {
        guard let store else { return }
        if let run = liveRuns.values.first(where: { $0.run.trigger == .chat(conversationID: id) }) { stop(run.id) }
        do {
            try await store.deleteConversation(id: id)
            conversations = try await store.conversations()
            if selectedConversationID == id { newConversation() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isEnabled else { return }
        draft = ""
        let now = clock.now
        let conversationID: UUID
        if let selectedConversationID {
            conversationID = selectedConversationID
        } else {
            conversationID = UUID()
            let title = String(text.prefix(48))
            let conversation = Conversation(id: conversationID, title: title, createdAt: now, updatedAt: now)
            try? await store?.saveConversation(conversation)
            selectedConversationID = conversationID
            conversations.insert(conversation, at: 0)
        }
        let history = chatEntries.map { $0.role == .user ? ChatMessage.user($0.text) : ChatMessage.assistant($0.text) }
        let entry = ChatEntry(id: UUID(), role: .user, text: text, runID: nil, createdAt: now)
        chatEntries.append(entry)
        await persist(entry, in: conversationID)

        // A reply to a run that asked for input continues that run.
        if let waiting = liveRuns.values.first(where: { $0.run.trigger == .chat(conversationID: conversationID) && !$0.isExecuting }) {
            resume(waiting.id, reply: text)
            return
        }
        startRun(trigger: .chat(conversationID: conversationID), instruction: text, criteria: nil, history: history, limits: settings.limits)
    }

    private func persist(_ entry: ChatEntry, in conversationID: UUID) async {
        guard let store else { return }
        do {
            try await store.appendMessage(StoredMessage(
                id: entry.id,
                conversationID: conversationID,
                role: entry.role,
                text: entry.text,
                runID: entry.runID,
                createdAt: entry.createdAt
            ))
            conversations = try await store.conversations()
        } catch {
            lastError = "The message could not be saved: \(error.localizedDescription)"
        }
    }

    // MARK: Runs

    func setupIssues() -> [String] {
        var issues = settings.setupIssues { storedCredentials.contains($0) }
        if settings.decisionKind == .managedLaya, !(componentStates[DecisionProviderSelection.defaultLayaCheckpoint]?.isInstalled ?? false) {
            issues.append("Install managed Laya in Settings.")
        }
        if settings.languageKind == .managedLocal {
            if !(componentStates["llama.cpp"]?.isInstalled ?? false) { issues.append("Install the local model runtime in Settings.") }
            let isImported = importedModels.contains { $0.id == settings.localModelID }
            if !isImported, !(componentStates[settings.localModelID]?.isInstalled ?? false) { issues.append("Install the local model in Settings.") }
        }
        if settings.usesHostedProvider && !settings.hostedDataDisclosureAccepted {
            issues.append("Review what is sent to hosted providers in Settings.")
        }
        return issues
    }

    @discardableResult
    private func startRun(
        trigger: RunTrigger,
        instruction: String,
        criteria: String?,
        history: [ChatMessage],
        limits: RunLimits,
        existing: AgentRun? = nil
    ) -> UUID? {
        let issues = setupIssues()
        guard issues.isEmpty, let factory else {
            lastError = issues.first ?? "The AI Agent is unavailable."
            return nil
        }
        let run = existing ?? AgentRun(trigger: trigger, instruction: instruction, status: .queued, startedAt: clock.now)
        let control = RunControl()
        var live = LiveRun(run: run, control: control, completionCriteria: criteria, limits: limits)
        live.resumeMessages = history
        liveRuns[run.id] = live
        let settings = self.settings
        let configuration = settings.configuration(limits: limits)
        let executor = configuration.computerUseEnabled ? self.executor : nil
        let environmentParts = (availability: availability, lease: lease, clock: clock)
        let runID = run.id

        let task = Task { [weak self] in
            let (updates, continuation) = AsyncStream.makeStream(of: AgentRunUpdate.self)
            let consumer = Task { [weak self] in
                for await update in updates { self?.apply(update, to: runID) }
            }
            let outcome: AgentRunOutcome
            do {
                let decision = try await factory.decisionProvider(for: settings)
                let language = try await factory.languageProvider(for: settings)
                let runner = AgentRunner(
                    task: AgentTask(
                        runID: runID,
                        trigger: trigger,
                        instruction: instruction,
                        completionCriteria: criteria,
                        history: history,
                        configuration: configuration
                    ),
                    environment: AgentEnvironment(
                        decision: decision,
                        language: language,
                        executor: executor,
                        availability: environmentParts.availability,
                        lease: environmentParts.lease,
                        clock: environmentParts.clock
                    ),
                    control: control,
                    onUpdate: { continuation.yield($0) }
                )
                outcome = await runner.run()
            } catch {
                outcome = AgentRunOutcome(
                    status: Self.status(forSetupError: error),
                    finalResponse: nil,
                    messages: history,
                    actionCount: 0
                )
            }
            continuation.finish()
            await consumer.value
            await self?.finish(runID, with: outcome)
        }
        liveRuns[run.id]?.task = task
        Task { await save(run) }
        return run.id
    }

    private static func status(forSetupError error: Error) -> RunStatus {
        if error is CancellationError { return .stopped }
        if let error = error as? DecisionProviderError { return .failed(message: error.userMessage) }
        if let error = error as? LanguageProviderError { return .failed(message: error.userMessage) }
        if let error = error as? RuntimeError { return .failed(message: error.userMessage) }
        if let error = error as? CredentialStoreError { return .failed(message: error.userMessage) }
        return .failed(message: error.localizedDescription)
    }

    private func apply(_ update: AgentRunUpdate, to runID: UUID) {
        guard var live = liveRuns[runID] else { return }
        switch update {
        case .status(let status):
            let previous = live.run.status
            if previous != status { live.run.transition(to: status, at: clock.now) }
            if case .needsInput = status { unacknowledgedOutcome = .needsInput }
            if previous != live.run.status {
                let run = live.run
                Task { await save(run) }
            }
        case .event(let event):
            live.run.events.append(event)
            if live.run.events.count > 500 { live.run.events.removeFirst(live.run.events.count - 500) }
        case .assistantText(let text):
            live.streamingText += text
        case .actionCount(let count):
            live.run.actionCount = count
        }
        liveRuns[runID] = live
    }

    private func finish(_ runID: UUID, with outcome: AgentRunOutcome) async {
        guard var live = liveRuns[runID] else { return }
        let now = clock.now
        live.task = nil
        live.streamingText = ""
        live.resumeMessages = outcome.messages
        if live.run.status != outcome.status, !live.run.transition(to: outcome.status, at: now) {
            live.run.status = outcome.status
            if outcome.status.isTerminal { live.run.endedAt = now }
        }
        live.run.actionCount = max(live.run.actionCount, outcome.actionCount)
        live.run.finalResponse = outcome.finalResponse ?? live.run.finalResponse

        if case .chat(let conversationID) = live.run.trigger {
            let text = Self.chatReply(for: outcome)
            if !text.isEmpty {
                let entry = ChatEntry(id: UUID(), role: .assistant, text: text, runID: runID, createdAt: now)
                if selectedConversationID == conversationID { chatEntries.append(entry) }
                await persist(entry, in: conversationID)
            }
        }
        if case .goal(let goalID) = live.run.trigger, let index = goals.firstIndex(where: { $0.id == goalID }) {
            goals[index].status = Self.goalStatus(for: outcome.status)
            goals[index].updatedAt = now
            let goal = goals[index]
            try? await store?.saveGoal(goal)
        }

        switch outcome.status {
        case .completed: unacknowledgedOutcome = .completed
        case .failed, .interrupted: unacknowledgedOutcome = .failed
        case .needsInput: unacknowledgedOutcome = .needsInput
        case .paused, .stopped, .queued, .running: break
        }

        await save(live.run)
        if outcome.status.isTerminal {
            liveRuns[runID] = nil
            recentRuns.removeAll { $0.id == runID }
            recentRuns.insert(live.run, at: 0)
        } else {
            liveRuns[runID] = live
        }
    }

    private static func chatReply(for outcome: AgentRunOutcome) -> String {
        switch outcome.status {
        case .completed(let evidence):
            let response = outcome.finalResponse ?? evidence
            return response == evidence || evidence.isEmpty ? response : "\(response)\n\nEvidence: \(evidence)"
        case .failed(let message): return "⚠︎ \(message)"
        case .needsInput(let reason): return outcome.finalResponse ?? reason.message
        case .paused(let reason): return reason ?? "Paused."
        case .stopped: return "Stopped. Completed actions were not undone."
        case .interrupted, .queued, .running: return ""
        }
    }

    private static func goalStatus(for status: RunStatus) -> GoalStatus {
        switch status {
        case .queued, .running: .running
        case .paused: .paused
        case .needsInput: .needsInput
        case .completed: .completed
        case .failed, .interrupted: .failed
        case .stopped: .cancelled
        }
    }

    private func save(_ run: AgentRun) async {
        do {
            try await store?.saveRun(run)
        } catch {
            lastError = "The run could not be saved: \(error.localizedDescription)"
        }
    }

    func pause(_ runID: UUID) {
        guard var live = liveRuns[runID], live.isExecuting else { return }
        let control = live.control
        Task { await control.pause() }
        live.run.transition(to: .paused(reason: "Paused by you"), at: clock.now)
        liveRuns[runID] = live
    }

    /// Resumes a paused run, or continues one that stopped to ask for input.
    func resume(_ runID: UUID, reply: String? = nil) {
        guard let live = liveRuns[runID] else { return }
        if live.isExecuting {
            let control = live.control
            Task { await control.resume() }
            liveRuns[runID]?.run.transition(to: .running, at: clock.now)
            return
        }
        var run = live.run
        run.transition(to: .running, at: clock.now)
        startRun(
            trigger: run.trigger,
            instruction: reply ?? "",
            criteria: live.completionCriteria,
            history: live.resumeMessages,
            limits: live.limits,
            existing: run
        )
    }

    func answerApproval(_ runID: UUID, approved: Bool) {
        guard let control = liveRuns[runID]?.control else { return }
        Task { await control.answerApproval(approved) }
    }

    /// Prevents further actions and cancels outstanding inference. Completed actions
    /// are not undone.
    func stop(_ runID: UUID) {
        guard let live = liveRuns[runID] else { return }
        let control = live.control
        Task { await control.stop() }
        live.task?.cancel()
        if !live.isExecuting {
            Task { await finish(runID, with: AgentRunOutcome(status: .stopped, finalResponse: nil, messages: live.resumeMessages, actionCount: live.run.actionCount)) }
        }
    }

    func stopAll() {
        liveRuns.keys.forEach(stop)
    }

    // MARK: Goals

    func saveGoal(_ goal: Goal) async {
        var goal = goal
        goal.updatedAt = clock.now
        if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = goal } else { goals.insert(goal, at: 0) }
        do { try await store?.saveGoal(goal) } catch { lastError = error.localizedDescription }
    }

    func deleteGoal(_ id: UUID) async {
        if let run = activeRun(forGoal: id) { stop(run.id) }
        goals.removeAll { $0.id == id }
        do { try await store?.deleteGoal(id: id) } catch { lastError = error.localizedDescription }
    }

    func runGoal(_ id: UUID) async {
        guard let index = goals.firstIndex(where: { $0.id == id }), activeRun(forGoal: id) == nil else { return }
        let goal = goals[index]
        guard let runID = startRun(
            trigger: .goal(goalID: id),
            instruction: goal.instruction,
            criteria: goal.completionCriteria,
            history: [],
            limits: goal.limits
        ) else { return }
        goals[index].status = .running
        goals[index].runIDs.append(runID)
        await saveGoal(goals[index])
    }

    func cancelGoal(_ id: UUID) async {
        if let run = activeRun(forGoal: id) { stop(run.id) }
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].status = .cancelled
        await saveGoal(goals[index])
    }

    func activeRun(forGoal id: UUID) -> LiveRun? {
        liveRuns.values.first { $0.run.trigger == .goal(goalID: id) }
    }

    func runs(forGoal id: UUID) async -> [AgentRun] {
        (try? await store?.runs(forGoal: id)) ?? []
    }

    // MARK: Routines

    func saveRoutine(_ routine: Routine) async {
        var routine = routine
        routine.updatedAt = clock.now
        if let index = routines.firstIndex(where: { $0.id == routine.id }) { routines[index] = routine } else { routines.append(routine) }
        do { try await store?.saveRoutine(routine) } catch { lastError = error.localizedDescription }
    }

    func deleteRoutine(_ id: UUID) async {
        if let run = activeRun(forRoutine: id) { stop(run.id) }
        routines.removeAll { $0.id == id }
        missedOccurrences.removeAll { $0.occurrence.key.routineID == id }
        do { try await store?.deleteRoutine(id: id) } catch { lastError = error.localizedDescription }
    }

    func setRoutineEnabled(_ id: UUID, enabled: Bool) async {
        guard var routine = routines.first(where: { $0.id == id }) else { return }
        routine.isEnabled = enabled
        await saveRoutine(routine)
    }

    func runRoutineNow(_ id: UUID, occurrence: OccurrenceKey? = nil) async {
        guard let routine = routines.first(where: { $0.id == id }), activeRun(forRoutine: id) == nil else { return }
        if let occurrence {
            try? await store?.resolveOccurrence(occurrence, as: .started, at: clock.now)
            missedOccurrences.removeAll { $0.occurrence.key == occurrence }
        }
        startRun(
            trigger: .routine(routineID: id, occurrence: occurrence),
            instruction: routine.instruction,
            criteria: nil,
            history: [],
            limits: routine.limits
        )
    }

    func dismissMissed(_ key: OccurrenceKey) async {
        try? await store?.resolveOccurrence(key, as: .dismissed, at: clock.now)
        missedOccurrences.removeAll { $0.occurrence.key == key }
    }

    func activeRun(forRoutine id: UUID) -> LiveRun? {
        liveRuns.values.first { if case .routine(id, _) = $0.run.trigger { true } else { false } }
    }

    func runs(forRoutine id: UUID) async -> [AgentRun] {
        (try? await store?.runs(forRoutine: id, limit: 20)) ?? []
    }

    func nextOccurrence(of routine: Routine) -> Date? {
        scheduler.nextOccurrence(of: routine, after: clock.now)?.scheduledAt
    }

    private func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.evaluateRoutines()
                let now = self.clock.now
                let next = self.scheduler.nextFireDate(for: self.routines, after: now)
                // Re-evaluate at least every minute so wake, clock, and time zone
                // changes are noticed promptly.
                let delay = min(max(next.map { $0.timeIntervalSince(now) } ?? 60, 1), 60)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Starts due routine occurrences, records missed ones, and never replays a backlog.
    func evaluateRoutines() async {
        guard isEnabled, let store else { return }
        let now = clock.now
        do {
            let last = try await store.schedulerCheckpoint() ?? now
            let handled = try await store.resolvedOccurrences()
            let active = Set(liveRuns.values.compactMap { live -> UUID? in
                if case .routine(let id, _) = live.run.trigger { id } else { nil }
            })
            let evaluation = scheduler.evaluate(
                routines: routines,
                lastEvaluatedAt: min(last, now),
                now: now,
                handled: handled,
                activeRoutineIDs: active
            )
            for occurrence in evaluation.due {
                try await store.resolveOccurrence(occurrence.key, as: .started, at: now)
                if let routine = routines.first(where: { $0.id == occurrence.key.routineID }) {
                    startRun(
                        trigger: .routine(routineID: routine.id, occurrence: occurrence.key),
                        instruction: routine.instruction,
                        criteria: nil,
                        history: [],
                        limits: routine.limits
                    )
                }
            }
            for occurrence in evaluation.missed {
                try await store.recordMissed(occurrence, at: now)
            }
            for occurrence in evaluation.overlapping {
                try await store.resolveOccurrence(occurrence.key, as: .skippedOverlap, at: now)
            }
            try await store.setSchedulerCheckpoint(now)
            if !evaluation.missed.isEmpty { missedOccurrences = try await store.missedOccurrences() }
            try await purgeIfNeeded()
        } catch {
            lastError = "Routines could not be scheduled: \(error.localizedDescription)"
        }
    }

    // MARK: History

    func clearHistory() async {
        guard let store else { return }
        do {
            try await store.clearHistory()
            conversations = []
            chatEntries = []
            selectedConversationID = nil
            recentRuns = []
            missedOccurrences = []
            goals = try await store.goals()
        } catch {
            lastError = "History could not be cleared: \(error.localizedDescription)"
        }
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: Credentials and providers

    func hasCredential(_ account: CredentialAccount) -> Bool { storedCredentials.contains(account) }

    func setCredential(_ secret: String, for account: CredentialAccount) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try credentials.setSecret(trimmed, for: account)
        } catch let error as CredentialStoreError {
            lastError = error.userMessage
        } catch {
            lastError = error.localizedDescription
        }
        refreshCredentialPresence()
    }

    /// Disconnecting removes the credential from Keychain.
    func removeCredential(_ account: CredentialAccount) {
        do {
            try credentials.removeSecret(for: account)
        } catch let error as CredentialStoreError {
            lastError = error.userMessage
        } catch {
            lastError = error.localizedDescription
        }
        refreshCredentialPresence()
    }

    private func refreshCredentialPresence() {
        storedCredentials = Set(CredentialAccount.allCases.filter { ((try? credentials.secret(for: $0)) ?? nil) != nil })
    }

    func refreshCatalog() async {
        guard let factory else { return }
        catalogStatus = "Loading models…"
        do {
            let settings = self.settings
            let provider: any LanguageModelProvider
            switch settings.languageKind {
            case .managedLocal:
                catalog = []
                catalogStatus = nil
                return
            case .openRouter:
                // OpenRouter's catalog is public, so it can be browsed before a key is added.
                provider = OpenAICompatibleLanguageProvider(
                    baseURL: OpenAICompatibleLanguageProvider.openRouterBaseURL,
                    apiKey: (try? credentials.secret(for: .openRouter)) ?? nil,
                    flavor: .openRouter
                )
            case .localEndpoint:
                provider = try await factory.languageProvider(for: settings)
            }
            let models = try await provider.models()
            let selected = settings.languageKind == .openRouter ? settings.openRouterModel : settings.localEndpointModel
            catalog = OpenRouterCatalog.merge(models, preserving: selected)
            catalogStatus = "\(models.count) models"
        } catch let error as LanguageProviderError {
            catalogStatus = error.userMessage
        } catch {
            catalogStatus = error.localizedDescription
        }
    }

    /// Checks both providers with real requests, including a tool call and, when the
    /// model may support images, a vision check.
    func testConnection() async {
        guard let factory else { return }
        isTestingConnection = true
        connectionStatus = "Testing…"
        defer { isTestingConnection = false }
        var lines: [String] = []
        let settings = self.settings
        do {
            let decision = try await factory.decisionProvider(for: settings)
            let response = try await decision.decide(DecisionRequest(
                state: #"{"note":"connection test"}"#,
                questions: [DecisionQuestion(id: "check", instructions: "Is this a connection test?", kind: .noul(whenTrue: nil, whenFalse: nil))]
            ))
            lines.append("Decisions: \(response.metadata.provider) responded (\(response.metadata.model)).")
        } catch let error as DecisionProviderError {
            lines.append("Decisions: \(error.userMessage)")
        } catch {
            lines.append("Decisions: \(error.localizedDescription)")
        }
        do {
            let language = try await factory.languageProvider(for: settings)
            let checkVision: Bool = switch settings.languageKind {
            case .openRouter: catalog.first { $0.id == settings.openRouterModel }?.capabilities.supportsVision ?? true
            case .managedLocal: true
            case .localEndpoint: true
            }
            let report = await CapabilityProbe(provider: language).run(model: settings.languageSelection.modelID, checkVision: checkVision)
            self.settings.capabilityReports[settings.capabilityKey] = report
            lines.append("Language model: \(report.detail)")
        } catch let error as LanguageProviderError {
            lines.append("Language model: \(error.userMessage)")
        } catch let error as RuntimeError {
            lines.append("Language model: \(error.userMessage)")
        } catch {
            lines.append("Language model: \(error.localizedDescription)")
        }
        connectionStatus = lines.joined(separator: "\n")
    }

    // MARK: Local components

    func refreshComponents() async {
        guard let runtimes else { return }
        componentStates = await runtimes.allStates()
        importedModels = await runtimes.importedModels()
    }

    func install(_ componentID: String) {
        guard let runtimes, installTasks[componentID] == nil else { return }
        installTasks[componentID] = Task { [weak self] in
            do {
                try await runtimes.install(componentID)
            } catch is CancellationError {
            } catch let error as RuntimeError {
                self?.lastError = error.userMessage
            } catch {
                self?.lastError = error.localizedDescription
            }
            self?.installTasks[componentID] = nil
            await self?.refreshComponents()
        }
    }

    func cancelInstall(_ componentID: String) {
        installTasks[componentID]?.cancel()
    }

    func isInstalling(_ componentID: String) -> Bool { installTasks[componentID] != nil }

    func removeComponent(_ componentID: String) async {
        guard let runtimes else { return }
        await factory?.stopManagedRuntimes()
        do {
            try await runtimes.remove(componentID)
        } catch {
            lastError = error.localizedDescription
        }
        await refreshComponents()
    }

    func importModel(from url: URL, projector: URL?) async {
        guard let runtimes else { return }
        do {
            let model = try await runtimes.importModel(from: url, projector: projector)
            await refreshComponents()
            connectionStatus = "Imported \(model.name). Select it and run Test connection before using it for computer tasks."
        } catch let error as RuntimeError {
            lastError = error.userMessage
        } catch {
            lastError = error.localizedDescription
        }
    }
}
