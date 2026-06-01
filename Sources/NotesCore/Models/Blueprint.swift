import Foundation

/// A blueprint that describes an initial folder structure and settings for notes-cli.
public struct Blueprint: Codable, Sendable {
    /// Top-level folders to create.
    public var folders: [BlueprintFolder]

    /// Optional settings to apply during initialization.
    public var settings: BlueprintSettings

    public init(folders: [BlueprintFolder], settings: BlueprintSettings) {
        self.folders = folders
        self.settings = settings
    }

    /// A folder entry in a blueprint, optionally nested.
    public struct BlueprintFolder: Codable, Sendable {
        public var name: String
        public var icon: String?
        public var children: [BlueprintFolder]?
        public var isProtected: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case icon
            case children
            case isProtected = "protected"
        }

        public init(
            name: String,
            icon: String? = nil,
            children: [BlueprintFolder]? = nil,
            isProtected: Bool? = nil
        ) {
            self.name = name
            self.icon = icon
            self.children = children
            self.isProtected = isProtected
        }
    }

    /// Settings embedded in a blueprint file.
    public struct BlueprintSettings: Codable, Sendable {
        public var softDelete: Bool?
        public var undoHistory: Int?
        public var lockedNotes: Bool?

        public init(
            softDelete: Bool? = nil,
            undoHistory: Int? = nil,
            lockedNotes: Bool? = nil
        ) {
            self.softDelete = softDelete
            self.undoHistory = undoHistory
            self.lockedNotes = lockedNotes
        }
    }

    /// Flattens nested folders into (path, folder, parentPath) tuples.
    public static func flattenFolders(
        _ folders: [BlueprintFolder],
        parentPath: String?
    ) -> [(path: String, folder: BlueprintFolder, parentPath: String?)] {
        var result: [(path: String, folder: BlueprintFolder, parentPath: String?)] = []
        for folder in folders {
            let path = parentPath.map { "\($0)/\(folder.name)" } ?? folder.name
            result.append((path, folder, parentPath))
            if let children = folder.children {
                result.append(contentsOf: flattenFolders(children, parentPath: path))
            }
        }
        return result
    }
}
