import Foundation

public enum NotesError: Error, LocalizedError, Sendable {
    case appleNotesUnavailable
    case noteNotFound(id: String)
    case folderNotFound(path: String)
    case databaseCorrupted(underlying: Error)
    case databaseMissing
    case scriptingBridgeError(message: String, number: Int?)
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
        case .databaseCorrupted(let underlying):
            return "Database is corrupted: \(underlying.localizedDescription)"
        case .databaseMissing:
            return "Database file is missing."
        case .scriptingBridgeError(let message, let number):
            if let number {
                return "Notes write error (\(number)): \(message)"
            }
            return "Notes write error: \(message)"
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
        case .noteNotFound, .folderNotFound, .configNotFound:
            return 1
        case .appleNotesUnavailable, .databaseCorrupted, .databaseMissing,
             .scriptingBridgeError, .encodingFailure:
            return 2
        case .commandFailed:
            return 1
        }
    }
}
