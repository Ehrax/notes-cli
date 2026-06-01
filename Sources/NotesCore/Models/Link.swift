import Foundation
import GRDB

public struct Link: Codable, Sendable, Equatable {
    public var id: Int64?
    public var sourceNoteID: String
    public var targetNoteID: String
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        sourceNoteID: String,
        targetNoteID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceNoteID = sourceNoteID
        self.targetNoteID = targetNoteID
        self.createdAt = createdAt
    }
}

extension Link: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "link"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
