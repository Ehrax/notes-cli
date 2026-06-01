import Foundation

/// Summary of an action for display in history listings.
public struct ActionSummary: Codable, Sendable {
    public var id: Int64?
    public var type: ActionType
    public var noteID: String
    public var timestamp: Date
    public var undone: Bool

    public init(id: Int64?, type: ActionType, noteID: String, timestamp: Date, undone: Bool) {
        self.id = id
        self.type = type
        self.noteID = noteID
        self.timestamp = timestamp
        self.undone = undone
    }

    /// Create a summary from a full ActionRecord.
    public init(from record: ActionRecord) {
        self.id = record.id
        self.type = record.actionType
        self.noteID = record.noteID
        self.timestamp = record.timestamp
        self.undone = record.undone
    }
}

/// Result of an undo operation.
public struct UndoResult: Codable, Sendable {
    /// The action that was reversed.
    public var actionID: Int64

    /// The type of the original action.
    public var originalType: ActionType

    /// Description of what the undo did.
    public var description: String

    public init(actionID: Int64, originalType: ActionType, description: String) {
        self.actionID = actionID
        self.originalType = originalType
        self.description = description
    }
}
