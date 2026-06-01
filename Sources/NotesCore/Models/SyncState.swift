import Foundation
import GRDB

public struct SyncState: Codable, Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

extension SyncState: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "syncState"
}
