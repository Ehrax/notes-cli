import Foundation
import GRDB

public enum ActionType: String, Codable, Sendable, DatabaseValueConvertible {
    case create
    case edit
    case delete
    case move
    case link
    case tag
    case untag
    case unlink
    case softDelete
}

public struct ActionRecord: Codable, Sendable, Equatable {
    public var id: Int64?
    public var actionType: ActionType
    public var noteID: String
    public var timestamp: Date
    public var beforeState: String?
    public var afterState: String?
    public var metadata: String?
    public var undone: Bool

    public init(
        id: Int64? = nil,
        actionType: ActionType,
        noteID: String,
        timestamp: Date = Date(),
        beforeState: String? = nil,
        afterState: String? = nil,
        metadata: String? = nil,
        undone: Bool = false
    ) {
        self.id = id
        self.actionType = actionType
        self.noteID = noteID
        self.timestamp = timestamp
        self.beforeState = beforeState
        self.afterState = afterState
        self.metadata = metadata
        self.undone = undone
    }
}

extension ActionRecord: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "actionLog"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
