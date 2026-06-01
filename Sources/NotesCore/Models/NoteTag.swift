import Foundation
import GRDB

public struct NoteTag: Codable, Sendable, Equatable {
    public var noteID: String
    public var tagID: Int64

    public init(noteID: String, tagID: Int64) {
        self.noteID = noteID
        self.tagID = tagID
    }
}

extension NoteTag: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "noteTag"
}
