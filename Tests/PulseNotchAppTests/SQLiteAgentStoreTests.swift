import Foundation
import PulseNotchCore
import SQLite3
import Testing
@testable import PulseNotchApp

struct SQLiteAgentStoreTests {
    private static let day: TimeInterval = 24 * 60 * 60
    private static let base = Date(timeIntervalSince1970: 1_750_000_000)

    private static func date(_ offset: TimeInterval) -> Date {
        base.addingTimeInterval(offset)
    }

    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteAgentStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func databaseURL(in directory: URL) -> URL {
        directory.appendingPathComponent("nested/agent.sqlite")
    }

    private static func configuration() -> AgentConfiguration {
        AgentConfiguration(
            decision: .layaEndpoint(url: URL(string: "http://127.0.0.1:8080") ?? URL(fileURLWithPath: "/"), model: "laya"),
            language: .openRouter(model: "example/model"),
            executionMode: .supervised,
            restrictions: ApplicationRestrictions(allowedBundleIDs: ["com.apple.Safari"], deniedBundleIDs: ["com.apple.Terminal"]),
            limits: RunLimits(maximumActions: 7, maximumDuration: 90, maximumReplans: 1),
            computerUseEnabled: false,
            visionVerified: true
        )
    }

    private static func run(
        trigger: RunTrigger,
        status: RunStatus,
        startedAt: Date,
        endedAt: Date? = nil,
        events: [ExecutionEvent] = []
    ) -> AgentRun {
        AgentRun(
            trigger: trigger,
            instruction: "Do the thing",
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            actionCount: 3,
            finalResponse: status.isTerminal ? "Done" : nil,
            events: events
        )
    }

    @Test
    func conversationsAndMessagesRoundTripInOrderAndCascadeOnDelete() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))

        let older = Conversation(id: UUID(), title: "Older", createdAt: Self.date(0), updatedAt: Self.date(10))
        let newer = Conversation(id: UUID(), title: "Newer", createdAt: Self.date(5), updatedAt: Self.date(20))
        try await store.saveConversation(older)
        try await store.saveConversation(newer)
        #expect(try await store.conversations().map(\.id) == [newer.id, older.id])

        let runID = UUID()
        let first = StoredMessage(id: UUID(), conversationID: older.id, role: .user, text: "Hello", runID: nil, createdAt: Self.date(30))
        let second = StoredMessage(id: UUID(), conversationID: older.id, role: .assistant, text: "Hi", runID: runID, createdAt: Self.date(40))
        try await store.appendMessage(second)
        try await store.appendMessage(first)

        #expect(try await store.messages(in: older.id) == [first, second])
        let conversations = try await store.conversations()
        #expect(conversations.map(\.id) == [older.id, newer.id])
        #expect(conversations.first?.updatedAt == Self.date(40))

        var renamed = older
        renamed.title = "Renamed"
        renamed.updatedAt = Self.date(50)
        try await store.saveConversation(renamed)
        #expect(try await store.conversations().first == renamed)
        #expect(try await store.messages(in: older.id).count == 2)

        try await store.deleteConversation(id: older.id)
        #expect(try await store.conversations() == [newer])
        #expect(try await store.messages(in: older.id).isEmpty)
    }

    @Test
    func appendingMessageToUnknownConversationFails() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))
        let orphan = StoredMessage(id: UUID(), conversationID: UUID(), role: .user, text: "Lost", runID: nil, createdAt: Self.date(0))

        await #expect(throws: AgentStoreError.self) {
            try await store.appendMessage(orphan)
        }
    }

    @Test
    func goalsAndRoutinesRoundTripUpsertAndDelete() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))

        let plainGoal = Goal(title: "Plain", instruction: "Tidy", completionCriteria: "Tidy desk", createdAt: Self.date(0))
        var configuredGoal = Goal(
            title: "Configured",
            instruction: "Book",
            completionCriteria: "Booking confirmed",
            configuration: Self.configuration(),
            limits: RunLimits(maximumActions: 12, maximumDuration: 300, maximumReplans: 3),
            status: .needsInput,
            runIDs: [UUID(), UUID()],
            createdAt: Self.date(100),
            updatedAt: Self.date(150)
        )
        try await store.saveGoal(plainGoal)
        try await store.saveGoal(configuredGoal)
        #expect(try await store.goals() == [configuredGoal, plainGoal])

        configuredGoal.status = .completed
        configuredGoal.title = "Configured again"
        try await store.saveGoal(configuredGoal)
        #expect(try await store.goals() == [configuredGoal, plainGoal])

        try await store.deleteGoal(id: plainGoal.id)
        #expect(try await store.goals() == [configuredGoal])

        var routine = Routine(
            title: "Standup notes",
            instruction: "Summarize",
            weekdays: [.monday, .wednesday, .friday],
            time: LocalTime(hour: 9, minute: 15),
            timeZoneIdentifier: "Europe/Rome",
            isEnabled: false,
            configuration: Self.configuration(),
            limits: RunLimits(maximumActions: 4, maximumDuration: 60, maximumReplans: 0),
            createdAt: Self.date(0)
        )
        let everyDay = Routine(title: "Daily", instruction: "Check", time: LocalTime(hour: 23, minute: 59), timeZoneIdentifier: "UTC", createdAt: Self.date(10))
        try await store.saveRoutine(routine)
        try await store.saveRoutine(everyDay)
        #expect(try await store.routines() == [routine, everyDay])

        routine.weekdays = [.sunday]
        routine.isEnabled = true
        routine.configuration = nil
        routine.updatedAt = Self.date(20)
        try await store.saveRoutine(routine)
        #expect(try await store.routines() == [routine, everyDay])

        let key = OccurrenceKey(routineID: routine.id, localDate: "2025-06-15")
        try await store.resolveOccurrence(key, as: .started, at: Self.date(30))
        try await store.recordMissed(RoutineOccurrence(key: OccurrenceKey(routineID: routine.id, localDate: "2025-06-16"), scheduledAt: Self.date(40)), at: Self.date(50))
        try await store.deleteRoutine(id: routine.id)
        #expect(try await store.routines() == [everyDay])
        #expect(try await store.resolvedOccurrences().isEmpty)
        #expect(try await store.missedOccurrences().isEmpty)
    }

    @Test
    func runsRoundTripWithEventsAndFilterByTrigger() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))

        let goalID = UUID()
        let routineID = UUID()
        let events = [
            ExecutionEvent(timestamp: Self.date(1), kind: .observed, summary: "Saw window"),
            ExecutionEvent(timestamp: Self.date(2), kind: .executed, summary: "Clicked")
        ]
        var goalRun = Self.run(trigger: .goal(goalID: goalID), status: .needsInput(.approval(actionSummary: "Send")), startedAt: Self.date(0), events: events)
        let chatRun = Self.run(trigger: .chat(conversationID: UUID()), status: .completed(evidence: "Screen shows done"), startedAt: Self.date(100), endedAt: Self.date(110))
        let olderRoutineRun = Self.run(
            trigger: .routine(routineID: routineID, occurrence: OccurrenceKey(routineID: routineID, localDate: "2025-06-15")),
            status: .failed(message: "Timeout"),
            startedAt: Self.date(200),
            endedAt: Self.date(210)
        )
        let newerRoutineRun = Self.run(trigger: .routine(routineID: routineID, occurrence: nil), status: .paused(reason: nil), startedAt: Self.date(300))

        for run in [goalRun, chatRun, olderRoutineRun, newerRoutineRun] {
            try await store.saveRun(run)
        }

        #expect(try await store.run(id: goalRun.id) == goalRun)
        #expect(try await store.run(id: UUID()) == nil)
        #expect(try await store.recentRuns(limit: 10).map(\.id) == [newerRoutineRun.id, olderRoutineRun.id, chatRun.id, goalRun.id])
        #expect(try await store.recentRuns(limit: 2).map(\.id) == [newerRoutineRun.id, olderRoutineRun.id])
        #expect(try await store.runs(forGoal: goalID) == [goalRun])
        #expect(try await store.runs(forRoutine: routineID, limit: 10) == [newerRoutineRun, olderRoutineRun])
        #expect(try await store.runs(forRoutine: routineID, limit: 1) == [newerRoutineRun])

        goalRun.events = [ExecutionEvent(timestamp: Self.date(3), kind: .verified, summary: "Checked")]
        goalRun.transition(to: .running, at: Self.date(4))
        goalRun.transition(to: .completed(evidence: "Sent"), at: Self.date(5))
        goalRun.finalResponse = "Sent the message"
        try await store.saveRun(goalRun)
        let reloaded = try await store.run(id: goalRun.id)
        #expect(reloaded == goalRun)
        #expect(reloaded?.events.count == 1)
    }

    @Test
    func markingUnfinishedRunsInterruptedLeavesTerminalRunsAlone() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))

        let running = Self.run(trigger: .goal(goalID: UUID()), status: .running, startedAt: Self.date(0))
        let paused = Self.run(trigger: .goal(goalID: UUID()), status: .paused(reason: "Wait"), startedAt: Self.date(10))
        let completed = Self.run(trigger: .goal(goalID: UUID()), status: .completed(evidence: "Ok"), startedAt: Self.date(20), endedAt: Self.date(25))
        for run in [running, paused, completed] {
            try await store.saveRun(run)
        }

        let interruptedAt = Self.date(1_000)
        let interrupted = try await store.markUnfinishedRunsInterrupted(at: interruptedAt)
        #expect(Set(interrupted.map(\.id)) == [running.id, paused.id])
        #expect(interrupted.allSatisfy { $0.status == .interrupted && $0.endedAt == interruptedAt })

        #expect(try await store.run(id: running.id)?.status == .interrupted)
        #expect(try await store.run(id: paused.id)?.endedAt == interruptedAt)
        #expect(try await store.run(id: completed.id) == completed)
        #expect(try await store.markUnfinishedRunsInterrupted(at: Self.date(2_000)).isEmpty)
    }

    @Test
    func occurrencesKeepLatestMissedPerRoutineAndResolutionClearsMissed() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))

        let routineA = UUID()
        let routineB = UUID()
        let startedKey = OccurrenceKey(routineID: routineA, localDate: "2025-06-14")
        try await store.resolveOccurrence(startedKey, as: .started, at: Self.date(0))
        try await store.resolveOccurrence(OccurrenceKey(routineID: routineB, localDate: "2025-06-14"), as: .skippedOverlap, at: Self.date(0))

        let missedA1 = RoutineOccurrence(key: OccurrenceKey(routineID: routineA, localDate: "2025-06-15"), scheduledAt: Self.date(Self.day))
        let missedA2 = RoutineOccurrence(key: OccurrenceKey(routineID: routineA, localDate: "2025-06-16"), scheduledAt: Self.date(2 * Self.day))
        let missedB = RoutineOccurrence(key: OccurrenceKey(routineID: routineB, localDate: "2025-06-15"), scheduledAt: Self.date(Self.day + 60))
        try await store.recordMissed(missedA1, at: Self.date(3 * Self.day))
        try await store.recordMissed(missedA2, at: Self.date(3 * Self.day))
        try await store.recordMissed(missedB, at: Self.date(3 * Self.day))
        try await store.recordMissed(missedA1, at: Self.date(4 * Self.day))
        try await store.recordMissed(RoutineOccurrence(key: startedKey, scheduledAt: Self.date(3 * Self.day)), at: Self.date(4 * Self.day))

        let missed = try await store.missedOccurrences()
        #expect(missed.map(\.occurrence) == [missedB, missedA2])
        #expect(missed.first?.recordedAt == Self.date(3 * Self.day))
        #expect(try await store.resolvedOccurrences().contains(startedKey))

        try await store.resolveOccurrence(missedA2.key, as: .dismissed, at: Self.date(5 * Self.day))
        #expect(try await store.missedOccurrences().map(\.occurrence) == [missedB])
        #expect(try await store.resolvedOccurrences() == [
            startedKey,
            OccurrenceKey(routineID: routineB, localDate: "2025-06-14"),
            missedA2.key
        ])
    }

    @Test
    func schedulerCheckpointPersistsAcrossReopening() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.databaseURL(in: directory)

        do {
            let store = try SQLiteAgentStore(databaseURL: url)
            #expect(try await store.schedulerCheckpoint() == nil)
            try await store.setSchedulerCheckpoint(Self.date(10))
            try await store.setSchedulerCheckpoint(Self.date(20))
        }

        let reopened = try SQLiteAgentStore(databaseURL: url)
        #expect(try await reopened.schedulerCheckpoint() == Self.date(20))
    }

    @Test
    func purgingHistoryRemovesOnlyItemsOlderThanTheRetentionWindow() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))
        let now = Self.date(60 * Self.day)
        let cutoff = now.addingTimeInterval(-30 * Self.day)
        let old = cutoff.addingTimeInterval(-Self.day)
        let recent = cutoff.addingTimeInterval(Self.day)

        let oldConversation = Conversation(id: UUID(), title: "Old", createdAt: old, updatedAt: old)
        let recentConversation = Conversation(id: UUID(), title: "Recent", createdAt: old, updatedAt: old)
        try await store.saveConversation(oldConversation)
        try await store.saveConversation(recentConversation)
        try await store.appendMessage(StoredMessage(id: UUID(), conversationID: oldConversation.id, role: .user, text: "a", runID: nil, createdAt: old))
        let recentMessage = StoredMessage(id: UUID(), conversationID: recentConversation.id, role: .user, text: "b", runID: nil, createdAt: recent)
        try await store.appendMessage(recentMessage)

        let oldGoal = Goal(title: "Old goal", instruction: "x", completionCriteria: "y", createdAt: old)
        let oldRoutine = Routine(title: "Old routine", instruction: "x", time: LocalTime(hour: 8, minute: 0), timeZoneIdentifier: "UTC", createdAt: old)
        try await store.saveGoal(oldGoal)
        try await store.saveRoutine(oldRoutine)

        let oldTerminal = Self.run(trigger: .goal(goalID: oldGoal.id), status: .stopped, startedAt: old, endedAt: old.addingTimeInterval(60),
                                   events: [ExecutionEvent(timestamp: old, kind: .status, summary: "Stopped")])
        let oldUnfinished = Self.run(trigger: .goal(goalID: oldGoal.id), status: .needsInput(.question("Which?")), startedAt: old)
        let recentTerminal = Self.run(trigger: .chat(conversationID: recentConversation.id), status: .completed(evidence: "ok"), startedAt: old, endedAt: recent)
        for run in [oldTerminal, oldUnfinished, recentTerminal] {
            try await store.saveRun(run)
        }

        let oldKey = OccurrenceKey(routineID: oldRoutine.id, localDate: "2025-06-01")
        let recentKey = OccurrenceKey(routineID: oldRoutine.id, localDate: "2025-07-10")
        try await store.resolveOccurrence(oldKey, as: .started, at: old)
        try await store.resolveOccurrence(recentKey, as: .dismissed, at: recent)

        try await store.purgeHistory(olderThan: cutoff)

        #expect(try await store.conversations().map(\.id) == [recentConversation.id])
        #expect(try await store.messages(in: oldConversation.id).isEmpty)
        #expect(try await store.messages(in: recentConversation.id) == [recentMessage])
        #expect(Set(try await store.recentRuns(limit: 10).map(\.id)) == [oldUnfinished.id, recentTerminal.id])
        #expect(try await store.run(id: oldTerminal.id) == nil)
        #expect(try await store.resolvedOccurrences() == [recentKey])
        #expect(try await store.goals() == [oldGoal])
        #expect(try await store.routines() == [oldRoutine])
    }

    @Test
    func clearingHistoryKeepsGoalsAndRoutinesButResetsRunIDs() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteAgentStore(databaseURL: Self.databaseURL(in: directory))

        let conversation = Conversation(id: UUID(), title: "Chat", createdAt: Self.date(0), updatedAt: Self.date(0))
        try await store.saveConversation(conversation)
        try await store.appendMessage(StoredMessage(id: UUID(), conversationID: conversation.id, role: .user, text: "hi", runID: nil, createdAt: Self.date(1)))
        let run = Self.run(trigger: .chat(conversationID: conversation.id), status: .running, startedAt: Self.date(2),
                           events: [ExecutionEvent(timestamp: Self.date(2), kind: .message, summary: "hi")])
        try await store.saveRun(run)
        let goal = Goal(title: "Goal", instruction: "x", completionCriteria: "y", runIDs: [run.id], createdAt: Self.date(0))
        let routine = Routine(title: "Routine", instruction: "x", time: LocalTime(hour: 7, minute: 30), timeZoneIdentifier: "UTC", createdAt: Self.date(0))
        try await store.saveGoal(goal)
        try await store.saveRoutine(routine)
        try await store.resolveOccurrence(OccurrenceKey(routineID: routine.id, localDate: "2025-06-15"), as: .started, at: Self.date(3))
        try await store.recordMissed(RoutineOccurrence(key: OccurrenceKey(routineID: routine.id, localDate: "2025-06-16"), scheduledAt: Self.date(4)), at: Self.date(5))

        try await store.clearHistory()

        #expect(try await store.conversations().isEmpty)
        #expect(try await store.messages(in: conversation.id).isEmpty)
        #expect(try await store.recentRuns(limit: 10).isEmpty)
        #expect(try await store.resolvedOccurrences().isEmpty)
        #expect(try await store.missedOccurrences().isEmpty)
        #expect(try await store.routines() == [routine])
        let goals = try await store.goals()
        #expect(goals.map(\.id) == [goal.id])
        #expect(goals.first?.runIDs == [])
    }

    @Test
    func migratingVersionOneDatabaseToVersionTwoPreservesData() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.databaseURL(in: directory)

        let conversation = Conversation(id: UUID(), title: "Kept", createdAt: Self.date(0), updatedAt: Self.date(0))
        let message = StoredMessage(id: UUID(), conversationID: conversation.id, role: .assistant, text: "Kept", runID: nil, createdAt: Self.date(1))
        let goal = Goal(title: "Kept goal", instruction: "x", completionCriteria: "y", configuration: Self.configuration(), createdAt: Self.date(2))
        let routine = Routine(title: "Kept routine", instruction: "x", weekdays: Weekday.weekdays, time: LocalTime(hour: 6, minute: 5), timeZoneIdentifier: "Asia/Tokyo", createdAt: Self.date(3))
        let runID = UUID()
        let trigger = RunTrigger.goal(goalID: goal.id)
        let status = RunStatus.completed(evidence: "Visible")

        do {
            let legacy = try SQLiteAgentStore(databaseURL: url, migrateTo: 1)
            #expect(try await legacy.schemaVersion() == 1)
            try await legacy.saveConversation(conversation)
            try await legacy.appendMessage(message)
            try await legacy.saveGoal(goal)
            try await legacy.saveRoutine(routine)
            try await legacy.setSchedulerCheckpoint(Self.date(4))
        }
        try Self.insertVersionOneRun(at: url, id: runID, trigger: trigger, status: status, startedAt: Self.date(5), endedAt: Self.date(6))

        let upgraded = try SQLiteAgentStore(databaseURL: url)
        #expect(try await upgraded.schemaVersion() == 2)
        #expect(try await upgraded.conversations().first?.id == conversation.id)
        #expect(try await upgraded.messages(in: conversation.id) == [message])
        #expect(try await upgraded.goals() == [goal])
        #expect(try await upgraded.routines() == [routine])
        #expect(try await upgraded.schedulerCheckpoint() == Self.date(4))

        let migratedRun = try #require(try await upgraded.run(id: runID))
        #expect(migratedRun.trigger == trigger)
        #expect(migratedRun.status == status)
        #expect(migratedRun.finalResponse == nil)
        #expect(try await upgraded.runs(forGoal: goal.id).map(\.id) == [runID])

        var finished = migratedRun
        finished.finalResponse = "Now stored"
        try await upgraded.saveRun(finished)
        #expect(try await upgraded.run(id: runID)?.finalResponse == "Now stored")
    }

    @Test
    func reopeningAnExistingDatabaseIsIdempotent() async throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.databaseURL(in: directory)
        let goal = Goal(title: "Persisted", instruction: "x", completionCriteria: "y", createdAt: Self.date(0))

        do {
            let store = try SQLiteAgentStore(databaseURL: url)
            try await store.saveGoal(goal)
        }
        for _ in 0..<2 {
            let store = try SQLiteAgentStore(databaseURL: url)
            #expect(try await store.schemaVersion() == SQLiteAgentStore.latestSchemaVersion)
            #expect(try await store.goals() == [goal])
        }
    }

    @Test
    func defaultLocationIsInsideApplicationSupport() {
        let path = SQLiteAgentStore.defaultURL().path
        #expect(path.hasSuffix("Application Support/Pulse Notch/AIAgent/agent.sqlite"))
    }

    /// Writes a run the way a version 1 build would, which had no `final_response` column.
    private static func insertVersionOneRun(
        at url: URL,
        id: UUID,
        trigger: RunTrigger,
        status: RunStatus,
        startedAt: Date,
        endedAt: Date
    ) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database = handle else {
            throw AgentStoreError.openFailed("test open")
        }
        defer { sqlite3_close_v2(database) }

        let encoder = JSONEncoder()
        let triggerJSON = String(decoding: try encoder.encode(trigger), as: UTF8.self)
        let statusJSON = String(decoding: try encoder.encode(status), as: UTF8.self)
        let sql = """
            INSERT INTO runs (id, trigger_kind, trigger_id, trigger, instruction, status, status_terminal,
                              started_at, ended_at, action_count)
            VALUES (?, 'goal', ?, ?, 'Legacy', ?, 1, ?, ?, 2)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            throw AgentStoreError.statementFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(prepared) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard case .goal(let goalID) = trigger else {
            throw AgentStoreError.corruptRecord("test expects a goal trigger")
        }
        sqlite3_bind_text(prepared, 1, id.uuidString, -1, transient)
        sqlite3_bind_text(prepared, 2, goalID.uuidString, -1, transient)
        sqlite3_bind_text(prepared, 3, triggerJSON, -1, transient)
        sqlite3_bind_text(prepared, 4, statusJSON, -1, transient)
        sqlite3_bind_double(prepared, 5, startedAt.timeIntervalSince1970)
        sqlite3_bind_double(prepared, 6, endedAt.timeIntervalSince1970)
        guard sqlite3_step(prepared) == SQLITE_DONE else {
            throw AgentStoreError.statementFailed(String(cString: sqlite3_errmsg(database)))
        }
    }
}
