import Foundation
import GRDB

public struct Folder: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var path: String
    public var parentPath: String?
    public var icon: String?
    public var isProtected: Bool
    public var sortOrder: Int

    public init(
        id: String,
        name: String,
        path: String,
        parentPath: String? = nil,
        icon: String? = nil,
        isProtected: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.parentPath = parentPath
        self.icon = icon
        self.isProtected = isProtected
        self.sortOrder = sortOrder
    }
}

extension Folder: FetchableRecord {
    public static let databaseTableName = "folder"
}
