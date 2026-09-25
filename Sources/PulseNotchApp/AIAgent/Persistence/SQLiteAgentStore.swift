import Foundation
import PulseNotchCore
import SQLite3

actor SQLiteAgentStore: AgentStore {
    struct Migration: Sendable {
        let version: Int
        let statements: [String]
    }

    static let migrations: [Migration] = [
        Migration(version: 1, statements: [
            """
            CREATE TABLE conversations (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE messages (
                id TEXT PRIMARY KEY NOT NULL,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                text TEXT NOT NULL,
                run_id TEXT,
                created_at REAL NOT NULL
            )
            """,
            "CREATE INDEX messages_by_conversation ON messages(conversation_id, created_at)",
            """
            CREATE TABLE goals (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                instruction TEXT NOT NULL,
                completion_criteria TEXT NOT NULL,
                configuration TEXT,
                limits TEXT NOT NULL,
                status TEXT NOT NULL,
                run_ids TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE routines (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                instruction TEXT NOT NULL,
                weekdays TEXT NOT NULL,
                hour INTEGER NOT NULL,
                minute INTEGER NOT NULL,
                time_zone TEXT NOT NULL,
                is_enabled INTEGER NOT NULL,
                configuration TEXT,
                limits TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE runs (
                id TEXT PRIMARY KEY NOT NULL,
                trigger_kind TEXT NOT NULL,
                trigger_id TEXT NOT NULL,
                trigger TEXT NOT NULL,
                instruction TEXT NOT NULL,
                status TEXT NOT NULL,
                status_terminal INTEGER NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL,
                action_count INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE run_events (
                run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                kind TEXT NOT NULL,
                summary TEXT NOT NULL,
                PRIMARY KEY (run_id, position)
            )
            """,
            """
            CREATE TABLE occurrences (
                routine_id TEXT NOT NULL,
                local_date TEXT NOT NULL,
                resolution TEXT NOT NULL,
                scheduled_at REAL,
                recorded_at REAL NOT NULL,
                PRIMARY KEY (routine_id, local_date)
            )
            """,
            """
            CREATE TABLE scheduler_state (
                name TEXT PRIMARY KEY NOT NULL,
                value REAL NOT NULL
            )
            """
        ]),
        Migration(version: 2, statements: [
            "ALTER TABLE runs ADD COLUMN final_response TEXT",
            "CREATE INDEX runs_by_start ON runs(started_at)",
            "CREATE INDEX runs_by_trigger ON runs(trigger_kind, trigger_id)"
        ])
    ]

    static var latestSchemaVersion: Int { migrations.map(\.version).max() ?? 0 }

    private static let checkpointName = "checkpoint"

    private let database: SQLiteDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(databaseURL: URL) throws {
        try self.init(databaseURL: databaseURL, migrateTo: Self.latestSchemaVersion)
    }

    /// Applies migrations only up to `targetVersion`, so tests can create older schemas.
    init(databaseURL: URL, migrateTo targetVersion: Int) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("PRAGMA journal_mode = WAL")
        try Self.migrate(database, to: targetVersion)
        self.database = database

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Pulse Notch", isDirectory: true)
            .appendingPathComponent("AIAgent", isDirectory: true)
            .appendingPathComponent("agent.sqlite", isDirectory: false)
    }

    func schemaVersion() throws -> Int {
        try Self.userVersion(of: database)
    }

    // MARK: Conversations

    func conversations() throws -> [Conversation] {
        try database.query(
            "SELECT id, title, created_at, updated_at FROM conversations ORDER BY updated_at DESC, id"
        ) { row in
            Conversation(
                id: try row.uuid(0),
                title: try row.text(1),
                createdAt: try row.date(2),
                updatedAt: try row.date(3)
            )
        }
    }

    func saveConversation(_ conversation: Conversation) throws {
        // An upsert rather than REPLACE: REPLACE deletes the row first, which would cascade to messages.
        try database.execute(
            """
            INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, updated_at = excluded.updated_at
            """,
            [
                .text(conversation.id.uuidString),
                .text(conversation.title),
                .date(conversation.createdAt),
                .date(conversation.updatedAt)
            ]
        )
    }

    func deleteConversation(id: UUID) throws {
        try database.execute("DELETE FROM conversations WHERE id = ?", [.text(id.uuidString)])
    }

    func messages(in conversationID: UUID) throws -> [StoredMessage] {
        try database.query(
            """
            SELECT id, conversation_id, role, text, run_id, created_at FROM messages
            WHERE conversation_id = ? ORDER BY created_at, rowid
            """,
            [.text(conversationID.uuidString)]
        ) { row in
            let roleValue = try row.text(2)
            guard let role = ChatRole(rawValue: roleValue) else {
                throw AgentStoreError.corruptRecord("Unknown message role \(roleValue)")
            }
            return StoredMessage(
                id: try row.uuid(0),
                conversationID: try row.uuid(1),
                role: role,
                text: try row.text(3),
                runID: try row.optionalUUID(4),
                createdAt: try row.date(5)
            )
        }
    }

    func appendMessage(_ message: StoredMessage) throws {
        try database.transaction {
            try database.execute(
                """
                INSERT INTO messages (id, conversation_id, role, text, run_id, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(message.id.uuidString),
                    .text(message.conversationID.uuidString),
                    .text(message.role.rawValue),
                    .text(message.text),
                    message.runID.map { .text($0.uuidString) } ?? .null,
                    .date(message.createdAt)
                ]
            )
            try database.execute(
                "UPDATE conversations SET updated_at = MAX(updated_at, ?) WHERE id = ?",
                [.date(message.createdAt), .text(message.conversationID.uuidString)]
            )
        }
    }

    // MARK: Goals

    func goals() throws -> [Goal] {
        try database.query(
            """
            SELECT id, title, instruction, completion_criteria, configuration, limits, status, run_ids,
                   created_at, updated_at
            FROM goals ORDER BY created_at DESC, id
            """
        ) { row in
            let statusValue = try row.text(6)
            guard let status = GoalStatus(rawValue: statusValue) else {
                throw AgentStoreError.corruptRecord("Unknown goal status \(statusValue)")
            }
            return Goal(
                id: try row.uuid(0),
                title: try row.text(1),
                instruction: try row.text(2),
                completionCriteria: try row.text(3),
                configuration: try decodeOptional(AgentConfiguration.self, row.optionalText(4)),
                limits: try decode(RunLimits.self, row.text(5)),
                status: status,
                runIDs: try decode([UUID].self, row.text(7)),
                createdAt: try row.date(8),
                updatedAt: try row.date(9)
            )
        }
    }

    func saveGoal(_ goal: Goal) throws {
        try database.execute(
            """
            INSERT INTO goals (id, title, instruction, completion_criteria, configuration, limits, status,
                               run_ids, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                instruction = excluded.instruction,
                completion_criteria = excluded.completion_criteria,
                configuration = excluded.configuration,
                limits = excluded.limits,
                status = excluded.status,
                run_ids = excluded.run_ids,
                updated_at = excluded.updated_at
            """,
            [
                .text(goal.id.uuidString),
                .text(goal.title),
                .text(goal.instruction),
                .text(goal.completionCriteria),
                try encodeOptional(goal.configuration),
                .text(try encode(goal.limits)),
                .text(goal.status.rawValue),
                .text(try encode(goal.runIDs)),
                .date(goal.createdAt),
                .date(goal.updatedAt)
            ]
        )
    }

    func deleteGoal(id: UUID) throws {
        try database.execute("DELETE FROM goals WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: Routines

    func routines() throws -> [Routine] {
        try database.query(
            """
            SELECT id, title, instruction, weekdays, hour, minute, time_zone, is_enabled, configuration,
                   limits, created_at, updated_at
            FROM routines ORDER BY created_at, id
            """
        ) { row in
            Routine(
                id: try row.uuid(0),
                title: try row.text(1),
                instruction: try row.text(2),
                weekdays: try decode(Set<Weekday>.self, row.text(3)),
                time: LocalTime(hour: row.int(4), minute: row.int(5)),
                timeZoneIdentifier: try row.text(6),
                isEnabled: row.int(7) != 0,
                configuration: try decodeOptional(AgentConfiguration.self, row.optionalText(8)),
                limits: try decode(RunLimits.self, row.text(9)),
                createdAt: try row.date(10),
                updatedAt: try row.date(11)
            )
        }
    }

    func saveRoutine(_ routine: Routine) throws {
        try database.execute(
            """
            INSERT INTO routines (id, title, instruction, weekdays, hour, minute, time_zone, is_enabled,
                                  configuration, limits, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                instruction = excluded.instruction,
                weekdays = excluded.weekdays,
                hour = excluded.hour,
                minute = excluded.minute,
                time_zone = excluded.time_zone,
                is_enabled = excluded.is_enabled,
                configuration = excluded.configuration,
                limits = excluded.limits,
                updated_at = excluded.updated_at
            """,
            [
                .text(routine.id.uuidString),
                .text(routine.title),
                .text(routine.instruction),
                .text(try encode(routine.weekdays.sorted())),
                .integer(Int64(routine.time.hour)),
                .integer(Int64(routine.time.minute)),
                .text(routine.timeZoneIdentifier),
                .integer(routine.isEnabled ? 1 : 0),
                try encodeOptional(routine.configuration),
                .text(try encode(routine.limits)),
                .date(routine.createdAt),
                .date(routine.updatedAt)
            ]
        )
    }

    func deleteRoutine(id: UUID) throws {
        try database.transaction {
            try database.execute("DELETE FROM occurrences WHERE routine_id = ?", [.text(id.uuidString)])
            try database.execute("DELETE FROM routines WHERE id = ?", [.text(id.uuidString)])
        }
    }

    // MARK: Runs

    func saveRun(_ run: AgentRun) throws {
        try database.transaction {
            try writeRun(run)
        }
    }

    func run(id: UUID) throws -> AgentRun? {
        try fetchRuns(where: "id = ?", [.text(id.uuidString)], limit: nil).first
    }

    func recentRuns(limit: Int) throws -> [AgentRun] {
        try fetchRuns(where: nil, [], limit: limit)
    }

    func runs(forGoal goalID: UUID) throws -> [AgentRun] {
        try fetchRuns(
            where: "trigger_kind = ? AND trigger_id = ?",
            [.text(TriggerKind.goal.rawValue), .text(goalID.uuidString)],
            limit: nil
        )
    }

    func runs(forRoutine routineID: UUID, limit: Int) throws -> [AgentRun] {
        try fetchRuns(
            where: "trigger_kind = ? AND trigger_id = ?",
            [.text(TriggerKind.routine.rawValue), .text(routineID.uuidString)],
            limit: limit
        )
    }

    func markUnfinishedRunsInterrupted(at date: Date) throws -> [AgentRun] {
        try database.transaction {
            let unfinished = try fetchRuns(where: "status_terminal = 0", [], limit: nil)
            return try unfinished.map { run in
                var interrupted = run
                interrupted.status = .interrupted
                interrupted.endedAt = date
                try writeRun(interrupted)
                return interrupted
            }
        }
    }

    // MARK: Occurrences

    func resolvedOccurrences() throws -> Set<OccurrenceKey> {
        let keys = try database.query(
            "SELECT routine_id, local_date FROM occurrences WHERE resolution != ?",
            [.text(OccurrenceResolution.missed.rawValue)]
        ) { row in
            OccurrenceKey(routineID: try row.uuid(0), localDate: try row.text(1))
        }
        return Set(keys)
    }

    func resolveOccurrence(_ key: OccurrenceKey, as resolution: OccurrenceResolution, at date: Date) throws {
        try database.execute(
            """
            INSERT INTO occurrences (routine_id, local_date, resolution, scheduled_at, recorded_at)
            VALUES (?, ?, ?, NULL, ?)
            ON CONFLICT(routine_id, local_date) DO UPDATE SET
                resolution = excluded.resolution,
                recorded_at = excluded.recorded_at
            """,
            [.text(key.routineID.uuidString), .text(key.localDate), .text(resolution.rawValue), .date(date)]
        )
    }

    func recordMissed(_ occurrence: RoutineOccurrence, at date: Date) throws {
        let routineID = Value.text(occurrence.key.routineID.uuidString)
        let missed = Value.text(OccurrenceResolution.missed.rawValue)
        try database.transaction {
            // An occurrence that was already resolved stays resolved and does not displace a missed one.
            let alreadyResolved = try database.query(
                "SELECT 1 FROM occurrences WHERE routine_id = ? AND local_date = ? AND resolution != ?",
                [routineID, .text(occurrence.key.localDate), missed]
            ) { _ in true }
            guard alreadyResolved.isEmpty else { return }

            let newerMissed = try database.query(
                """
                SELECT 1 FROM occurrences
                WHERE routine_id = ? AND resolution = ? AND scheduled_at > ? AND local_date != ?
                LIMIT 1
                """,
                [routineID, missed, .date(occurrence.scheduledAt), .text(occurrence.key.localDate)]
            ) { _ in true }
            guard newerMissed.isEmpty else { return }

            try database.execute(
                "DELETE FROM occurrences WHERE routine_id = ? AND resolution = ? AND local_date != ?",
                [routineID, missed, .text(occurrence.key.localDate)]
            )
            try database.execute(
                """
                INSERT INTO occurrences (routine_id, local_date, resolution, scheduled_at, recorded_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(routine_id, local_date) DO UPDATE SET
                    scheduled_at = excluded.scheduled_at,
                    recorded_at = excluded.recorded_at
                """,
                [routineID, .text(occurrence.key.localDate), missed, .date(occurrence.scheduledAt), .date(date)]
            )
        }
    }

    func missedOccurrences() throws -> [MissedOccurrence] {
        try database.query(
            """
            SELECT routine_id, local_date, scheduled_at, recorded_at FROM occurrences
            WHERE resolution = ? AND scheduled_at IS NOT NULL
            ORDER BY scheduled_at, routine_id
            """,
            [.text(OccurrenceResolution.missed.rawValue)]
        ) { row in
            MissedOccurrence(
                occurrence: RoutineOccurrence(
                    key: OccurrenceKey(routineID: try row.uuid(0), localDate: try row.text(1)),
                    scheduledAt: try row.date(2)
                ),
                recordedAt: try row.date(3)
            )
        }
    }

    // MARK: Scheduler

    func schedulerCheckpoint() throws -> Date? {
        try database.query(
            "SELECT value FROM scheduler_state WHERE name = ?",
            [.text(Self.checkpointName)]
        ) { row in try row.date(0) }.first
    }

    func setSchedulerCheckpoint(_ date: Date) throws {
        try database.execute(
            """
            INSERT INTO scheduler_state (name, value) VALUES (?, ?)
            ON CONFLICT(name) DO UPDATE SET value = excluded.value
            """,
            [.text(Self.checkpointName), .date(date)]
        )
    }

    // MARK: Retention

    func purgeHistory(olderThan cutoff: Date) throws {
        try database.transaction {
            try database.execute("DELETE FROM conversations WHERE updated_at < ?", [.date(cutoff)])
            try database.execute(
                "DELETE FROM runs WHERE status_terminal = 1 AND ended_at IS NOT NULL AND ended_at < ?",
                [.date(cutoff)]
            )
            try database.execute("DELETE FROM occurrences WHERE recorded_at < ?", [.date(cutoff)])
        }
    }

    func clearHistory() throws {
        try database.transaction {
            try database.execute("DELETE FROM messages")
            try database.execute("DELETE FROM conversations")
            try database.execute("DELETE FROM run_events")
            try database.execute("DELETE FROM runs")
            try database.execute("DELETE FROM occurrences")
            try database.execute("UPDATE goals SET run_ids = ?", [.text(try encode([UUID]()))])
        }
    }

    // MARK: Run rows

    private enum TriggerKind: String {
        case chat
        case goal
        case routine
    }

    private func triggerColumns(_ trigger: RunTrigger) -> (kind: TriggerKind, id: UUID) {
        switch trigger {
        case .chat(let conversationID): (.chat, conversationID)
        case .goal(let goalID): (.goal, goalID)
        case .routine(let routineID, _): (.routine, routineID)
        }
    }

    private func writeRun(_ run: AgentRun) throws {
        let trigger = triggerColumns(run.trigger)
        let runID = Value.text(run.id.uuidString)
        try database.execute(
            """
            INSERT INTO runs (id, trigger_kind, trigger_id, trigger, instruction, status, status_terminal,
                              started_at, ended_at, action_count, final_response)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                trigger_kind = excluded.trigger_kind,
                trigger_id = excluded.trigger_id,
                trigger = excluded.trigger,
                instruction = excluded.instruction,
                status = excluded.status,
                status_terminal = excluded.status_terminal,
                started_at = excluded.started_at,
                ended_at = excluded.ended_at,
                action_count = excluded.action_count,
                final_response = excluded.final_response
            """,
            [
                runID,
                .text(trigger.kind.rawValue),
                .text(trigger.id.uuidString),
                .text(try encode(run.trigger)),
                .text(run.instruction),
                .text(try encode(run.status)),
                .integer(run.status.isTerminal ? 1 : 0),
                .date(run.startedAt),
                run.endedAt.map(Value.date) ?? .null,
                .integer(Int64(run.actionCount)),
                run.finalResponse.map(Value.text) ?? .null
            ]
        )
        try database.execute("DELETE FROM run_events WHERE run_id = ?", [runID])
        for (position, event) in run.events.enumerated() {
            try database.execute(
                """
                INSERT INTO run_events (run_id, position, id, timestamp, kind, summary)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    runID,
                    .integer(Int64(position)),
                    .text(event.id.uuidString),
                    .date(event.timestamp),
                    .text(event.kind.rawValue),
                    .text(event.summary)
                ]
            )
        }
    }

    /// `condition` is always a constant SQL fragment from this file; values are bound separately.
    private func fetchRuns(where condition: String?, _ values: [Value], limit: Int?) throws -> [AgentRun] {
        var sql = """
            SELECT id, trigger, instruction, status, started_at, ended_at, action_count, final_response
            FROM runs
            """
        var bindings = values
        if let condition {
            sql += " WHERE \(condition)"
        }
        sql += " ORDER BY started_at DESC, id"
        if let limit {
            sql += " LIMIT ?"
            bindings.append(.integer(Int64(max(0, limit))))
        }
        let rows = try database.query(sql, bindings) { row in
            AgentRun(
                id: try row.uuid(0),
                trigger: try decode(RunTrigger.self, row.text(1)),
                instruction: try row.text(2),
                status: try decode(RunStatus.self, row.text(3)),
                startedAt: try row.date(4),
                endedAt: row.optionalDate(5),
                actionCount: row.int(6),
                finalResponse: row.optionalText(7)
            )
        }
        return try rows.map { run in
            var complete = run
            complete.events = try events(forRun: run.id)
            return complete
        }
    }

    private func events(forRun runID: UUID) throws -> [ExecutionEvent] {
        try database.query(
            "SELECT id, timestamp, kind, summary FROM run_events WHERE run_id = ? ORDER BY position",
            [.text(runID.uuidString)]
        ) { row in
            let kindValue = try row.text(2)
            guard let kind = ExecutionEvent.Kind(rawValue: kindValue) else {
                throw AgentStoreError.corruptRecord("Unknown event kind \(kindValue)")
            }
            return ExecutionEvent(
                id: try row.uuid(0),
                timestamp: try row.date(1),
                kind: kind,
                summary: try row.text(3)
            )
        }
    }

    // MARK: JSON

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AgentStoreError.corruptRecord("Could not encode \(T.self) as UTF-8")
        }
        return string
    }

    private func encodeOptional<T: Encodable>(_ value: T?) throws -> Value {
        guard let value else { return .null }
        return .text(try encode(value))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ string: String) throws -> T {
        do {
            return try decoder.decode(type, from: Data(string.utf8))
        } catch {
            throw AgentStoreError.corruptRecord("Could not decode \(T.self): \(error.localizedDescription)")
        }
    }

    private func decodeOptional<T: Decodable>(_ type: T.Type, _ string: String?) throws -> T? {
        guard let string else { return nil }
        return try decode(type, string)
    }

    // MARK: Migrations

    private static func userVersion(of database: SQLiteDatabase) throws -> Int {
        try database.query("PRAGMA user_version") { row in row.int(0) }.first ?? 0
    }

    private static func migrate(_ database: SQLiteDatabase, to targetVersion: Int) throws {
        let current = try userVersion(of: database)
        guard current <= latestSchemaVersion else {
            throw AgentStoreError.openFailed(
                "Database schema version \(current) is newer than supported version \(latestSchemaVersion)"
            )
        }
        let pending = migrations
            .filter { $0.version > current && $0.version <= targetVersion }
            .sorted { $0.version < $1.version }
        for migration in pending {
            try database.transaction {
                for statement in migration.statements {
                    try database.execute(statement)
                }
                // PRAGMA statements cannot take bound parameters; the version is a constant from `migrations`.
                try database.execute("PRAGMA user_version = \(migration.version)")
            }
        }
    }
}

// MARK: - SQLite access

extension SQLiteAgentStore {
    enum Value {
        case text(String)
        case real(Double)
        case integer(Int64)
        case null

        static func date(_ date: Date) -> Value { .real(date.timeIntervalSince1970) }
    }

    struct Row {
        fileprivate let statement: OpaquePointer

        func optionalText(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL,
                  let pointer = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: pointer)
        }

        func text(_ column: Int32) throws -> String {
            guard let value = optionalText(column) else {
                throw AgentStoreError.corruptRecord("Missing text in column \(column)")
            }
            return value
        }

        func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }

        func optionalDate(_ column: Int32) -> Date? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
            return Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
        }

        func date(_ column: Int32) throws -> Date {
            guard let value = optionalDate(column) else {
                throw AgentStoreError.corruptRecord("Missing timestamp in column \(column)")
            }
            return value
        }

        func optionalUUID(_ column: Int32) throws -> UUID? {
            guard let value = optionalText(column) else { return nil }
            guard let uuid = UUID(uuidString: value) else {
                throw AgentStoreError.corruptRecord("Invalid identifier \(value)")
            }
            return uuid
        }

        func uuid(_ column: Int32) throws -> UUID {
            guard let value = try optionalUUID(column) else {
                throw AgentStoreError.corruptRecord("Missing identifier in column \(column)")
            }
            return value
        }
    }

    /// Owns the SQLite connection so it is closed when the store is released.
    /// `@unchecked Sendable` is sound because only `SQLiteAgentStore` holds it, and every
    /// use after initialization happens on that actor; the connection is also opened FULLMUTEX.
    final class SQLiteDatabase: @unchecked Sendable {
        private let handle: OpaquePointer
        private var transactionDepth = 0

        init(url: URL) throws {
            var pointer: OpaquePointer?
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            let result = sqlite3_open_v2(url.path, &pointer, flags, nil)
            guard result == SQLITE_OK, let pointer else {
                let message = pointer.map { String(cString: sqlite3_errmsg($0)) }
                    ?? String(cString: sqlite3_errstr(result))
                if let pointer { sqlite3_close_v2(pointer) }
                throw AgentStoreError.openFailed(message)
            }
            handle = pointer
            sqlite3_busy_timeout(handle, 5_000)
        }

        deinit {
            sqlite3_close_v2(handle)
        }

        func execute(_ sql: String, _ values: [Value] = []) throws {
            let statement = try prepare(sql, values)
            defer { sqlite3_finalize(statement) }
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                result = sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else { throw statementError() }
        }

        func query<T>(_ sql: String, _ values: [Value] = [], map: (Row) throws -> T) throws -> [T] {
            let statement = try prepare(sql, values)
            defer { sqlite3_finalize(statement) }
            var results: [T] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw statementError() }
                results.append(try map(Row(statement: statement)))
            }
            return results
        }

        /// Nested calls join the outermost transaction.
        func transaction<T>(_ body: () throws -> T) throws -> T {
            if transactionDepth > 0 {
                transactionDepth += 1
                defer { transactionDepth -= 1 }
                return try body()
            }
            try execute("BEGIN IMMEDIATE")
            transactionDepth = 1
            defer { transactionDepth = 0 }
            do {
                let result = try body()
                try execute("COMMIT")
                return result
            } catch {
                sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
                throw error
            }
        }

        private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw statementError()
            }
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let result: Int32 = switch value {
                case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
                case .real(let real): sqlite3_bind_double(statement, index, real)
                case .integer(let integer): sqlite3_bind_int64(statement, index, integer)
                case .null: sqlite3_bind_null(statement, index)
                }
                guard result == SQLITE_OK else {
                    let error = statementError()
                    sqlite3_finalize(statement)
                    throw error
                }
            }
            return statement
        }

        private func statementError() -> AgentStoreError {
            .statementFailed(String(cString: sqlite3_errmsg(handle)))
        }

        /// Tells SQLite to copy bound text, because Swift strings are only valid during the call.
        private static var transient: sqlite3_destructor_type {
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        }
    }
}
