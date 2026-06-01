import Foundation

/// Protocol for safety operations: folder protection, note locking, soft-delete, action logging, and undo.
public protocol SafetyServiceProtocol: Sendable {
    /// Throws `NotesError.protectedFolder` if the folder is protected.
    func guardWrite(toFolder folderPath: String) async throws

    /// Throws `NotesError.noteLocked` if the note is locked and config.lockedNotes is enabled.
    func guardLocked(noteID: String, isLocked: Bool) async throws

    /// Soft-deletes a note by recording its state and moving it to Archive.
    func softDelete(noteID: String) async throws

    /// Records an action in the action log for undo support.
    func recordAction(
        type: ActionType,
        noteID: String,
        before: Checkpoint?,
        after: Checkpoint?,
        metadata: [String: String]?
    ) async throws

    /// Undoes the last non-undone action. Returns nil if nothing to undo.
    func undoLast() async throws -> UndoResult?

    /// Returns action history, optionally filtered by noteID.
    func history(noteID: String?, limit: Int) async throws -> [ActionSummary]
}
