import Foundation
import GRDB

public struct Folder: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var path: String
    public var parentPath: String?

    public init(
        id: String,
        name: String,
        path: String,
        parentPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.parentPath = parentPath
    }
}

extension Folder: FetchableRecord {}
