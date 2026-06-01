import Foundation
import GRDB

public struct NoteAttachment: Codable, Sendable, Equatable {
    public var id: String
    public var noteID: String
    public var filename: String?
    public var typeUTI: String?
    public var relativePath: String

    public init(id: String, noteID: String, filename: String?, typeUTI: String?, relativePath: String) {
        self.id = id
        self.noteID = noteID
        self.filename = filename
        self.typeUTI = typeUTI
        self.relativePath = relativePath
    }
}

extension NoteAttachment: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "noteAttachment"
}
