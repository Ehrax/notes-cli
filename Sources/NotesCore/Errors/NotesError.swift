import Foundation

public enum NotesError: Error, LocalizedError, Sendable {
    case appleNotesUnavailable
    case noteNotFound(id: String)
    case folderNotFound(path: String)
    case protectedFolder(path: String)
    case noteLocked(id: String)
    case databaseCorrupted(underlying: Error)
    case databaseMissing
    case reminderPermissionDenied
    case blueprintInvalid(reason: String)
    case appleScriptError(message: String, number: Int?)
    case syncConflict(noteID: String, reason: String)
    case nothingToUndo
    case configNotFound
    case encodingFailure(reason: String)
    case commandFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .appleNotesUnavailable:
            return "Apple Notes is not available on this system."
        case .noteNotFound(let id):
            return "Note not found: \(id)"
        case .folderNotFound(let path):
            return "Folder not found: \(path)"
        case .protectedFolder(let path):
            return "Folder is protected: \(path)"
        case .noteLocked(let id):
            return "Note is locked: \(id)"
        case .databaseCorrupted(let underlying):
            return "Database is corrupted: \(underlying.localizedDescription)"
        case .databaseMissing:
            return "Database file is missing."
        case .reminderPermissionDenied:
            return "Reminder permission denied."
        case .blueprintInvalid(let reason):
            return "Blueprint is invalid: \(reason)"
        case .appleScriptError(let message, let number):
            if let number {
                return "AppleScript error (\(number)): \(message)"
            }
            return "AppleScript error: \(message)"
        case .syncConflict(let noteID, let reason):
            return "Sync conflict for note \(noteID): \(reason)"
        case .nothingToUndo:
            return "Nothing to undo."
        case .configNotFound:
            return "Configuration not found."
        case .encodingFailure(let reason):
            return "Encoding failure: \(reason)"
        case .commandFailed(let message):
            return message
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .noteNotFound, .folderNotFound, .protectedFolder, .noteLocked,
             .blueprintInvalid, .syncConflict, .nothingToUndo, .configNotFound:
            return 1
        case .appleNotesUnavailable, .databaseCorrupted, .databaseMissing,
             .reminderPermissionDenied, .appleScriptError, .encodingFailure:
            return 2
        case .commandFailed:
            return 1
        }
    }
}
