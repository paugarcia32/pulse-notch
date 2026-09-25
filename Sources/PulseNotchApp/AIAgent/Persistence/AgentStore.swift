import Foundation
import PulseNotchCore

struct Conversation: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
}

struct StoredMessage: Hashable, Sendable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let role: ChatRole
    let text: String
    let runID: UUID?
    let createdAt: Date
}

enum OccurrenceResolution: String, Codable, Sendable {
    case started
    case dismissed
    case skippedOverlap
    case missed
}

struct MissedOccurrence: Hashable, Sendable {
    let occurrence: RoutineOccurrence
    let recordedAt: Date
}

enum AgentStoreError: Error, Equatable {
    case openFailed(String)
    case statementFailed(String)
    case corruptRecord(String)
}

/// Durable storage for the AI agent's conversations, goals, routines, runs, and
/// scheduler bookkeeping. Screenshots and credentials are never persisted here.
protocol AgentStore: Sendable {
    /// Newest `updatedAt` first.
    func conversations() async throws -> [Conversation]
    func saveConversation(_ conversation: Conversation) async throws
    /// Also deletes the conversation's messages.
    func deleteConversation(id: UUID) async throws
    /// Oldest first.
    func messages(in conversationID: UUID) async throws -> [StoredMessage]
    /// Also moves the conversation's `updatedAt` forward to the message's `createdAt`.
    func appendMessage(_ message: StoredMessage) async throws

    /// Newest `createdAt` first.
    func goals() async throws -> [Goal]
    func saveGoal(_ goal: Goal) async throws
    func deleteGoal(id: UUID) async throws
    func routines() async throws -> [Routine]
    func saveRoutine(_ routine: Routine) async throws
    /// Also deletes the routine's occurrence records.
    func deleteRoutine(id: UUID) async throws

    /// Inserts or replaces the run together with its complete event list.
    func saveRun(_ run: AgentRun) async throws
    func run(id: UUID) async throws -> AgentRun?
    /// Newest `startedAt` first.
    func recentRuns(limit: Int) async throws -> [AgentRun]
    func runs(forGoal goalID: UUID) async throws -> [AgentRun]
    func runs(forRoutine routineID: UUID, limit: Int) async throws -> [AgentRun]
    /// Marks every run whose status is not terminal as `.interrupted` (endedAt = date) and returns them.
    func markUnfinishedRunsInterrupted(at date: Date) async throws -> [AgentRun]

    /// Every occurrence resolved as anything other than `.missed`.
    func resolvedOccurrences() async throws -> Set<OccurrenceKey>
    /// Resolving an occurrence removes it from the missed list.
    func resolveOccurrence(_ key: OccurrenceKey, as resolution: OccurrenceResolution, at date: Date) async throws
    /// Keeps only the latest missed occurrence per routine.
    func recordMissed(_ occurrence: RoutineOccurrence, at date: Date) async throws
    /// Oldest `scheduledAt` first.
    func missedOccurrences() async throws -> [MissedOccurrence]

    func schedulerCheckpoint() async throws -> Date?
    func setSchedulerCheckpoint(_ date: Date) async throws

    /// Deletes conversations (and messages) whose updatedAt is before the cutoff, terminal runs (and events) that ended before it, and occurrence rows older than it. Never deletes goals or routines.
    func purgeHistory(olderThan cutoff: Date) async throws
    /// Deletes all conversations, messages, runs, events, and occurrence rows. Keeps goals and routines, and resets goals' runIDs to [].
    func clearHistory() async throws
}
