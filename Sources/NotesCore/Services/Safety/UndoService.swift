import Foundation

/// Determines the reverse operation for a given ActionRecord.
public struct UndoService: Sendable {

    /// Describes the operation needed to reverse an action.
    public enum ReverseOp: Sendable {
        /// Delete the note that was created.
        case deleteNote(noteID: String)

        /// Restore the note to its before-state (edit reversal).
        case restoreNote(checkpoint: Checkpoint)

        /// Recreate a deleted note from its before-state.
        case recreateNote(checkpoint: Checkpoint)

        /// Move the note back to its original folder.
        case moveNote(noteID: String, toFolder: String)
    }

    /// Computes the reverse operation for a given action record.
    /// - Parameter record: The action to reverse.
    /// - Returns: The operation that undoes this action.
    /// - Throws: `NotesError.nothingToUndo` if the action cannot be reversed.
    public static func reverseOperation(for record: ActionRecord) throws -> ReverseOp {
        switch record.actionType {
        case .create:
            // Reverse of create is delete
            return .deleteNote(noteID: record.noteID)

        case .edit:
            // Reverse of edit is restore to before-state
            guard let beforeJSON = record.beforeState else {
                throw NotesError.nothingToUndo
            }
            let checkpoint = try ActionLogger.decodeCheckpoint(from: beforeJSON)
            return .restoreNote(checkpoint: checkpoint)

        case .delete:
            // Reverse of delete is recreate from before-state
            guard let beforeJSON = record.beforeState else {
                throw NotesError.nothingToUndo
            }
            let checkpoint = try ActionLogger.decodeCheckpoint(from: beforeJSON)
            return .recreateNote(checkpoint: checkpoint)

        case .softDelete:
            // Reverse of soft delete is restoring the archived original note
            guard let beforeJSON = record.beforeState else {
                throw NotesError.nothingToUndo
            }
            let checkpoint = try ActionLogger.decodeCheckpoint(from: beforeJSON)
            return .moveNote(noteID: record.noteID, toFolder: checkpoint.folderPath)

        case .move:
            // Reverse of move is move back to original folder
            guard let beforeJSON = record.beforeState else {
                throw NotesError.nothingToUndo
            }
            let checkpoint = try ActionLogger.decodeCheckpoint(from: beforeJSON)
            return .moveNote(noteID: record.noteID, toFolder: checkpoint.folderPath)

        case .link, .tag, .untag, .unlink:
            // These are not yet undoable
            throw NotesError.nothingToUndo
        }
    }

    /// Generates a human-readable description for an undo result.
    public static func description(for action: ActionType, noteID: String) -> String {
        switch action {
        case .create:
            return "Undid creation of note \(noteID) (deleted)"
        case .edit:
            return "Undid edit of note \(noteID) (restored previous version)"
        case .delete:
            return "Undid deletion of note \(noteID) (recreated)"
        case .softDelete:
            return "Undid deletion of note \(noteID) (restored original)"
        case .move:
            return "Undid move of note \(noteID) (moved back)"
        case .link:
            return "Undid link involving note \(noteID)"
        case .tag:
            return "Undid tag on note \(noteID)"
        case .untag:
            return "Undid untag on note \(noteID)"
        case .unlink:
            return "Undid unlink involving note \(noteID)"
        }
    }
}
