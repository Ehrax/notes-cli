import Foundation
import GRDB

public struct Tag: Codable, Sendable, Equatable {
    public var id: Int64?
    public var name: String

    public init(id: Int64? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

extension Tag: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "tag"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
