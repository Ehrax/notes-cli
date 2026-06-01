import Foundation

/// Raw data from Apple Notes before processing into our Note model.
public struct AppleNoteMetadata: Sendable {
    public var id: String
    public var name: String
    public var folderName: String
    public var folderPath: String
    public var accountName: String?
    public var creationDate: Date
    public var modificationDate: Date
    public var isLocked: Bool

    public init(
        id: String,
        name: String,
        folderName: String,
        folderPath: String,
        accountName: String? = nil,
        creationDate: Date,
        modificationDate: Date,
        isLocked: Bool
    ) {
        self.id = id
        self.name = name
        self.folderName = folderName
        self.folderPath = folderPath
        self.accountName = accountName
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isLocked = isLocked
    }
}

public struct AppleNoteRaw: Sendable {
    public var id: String
    public var name: String
    public var bodyProtobuf: Data
    public var bodyPlaintext: String
    public var folderName: String
    public var folderPath: String
    public var accountName: String?
    public var snippet: String?
    public var creationDate: Date
    public var modificationDate: Date
    public var isLocked: Bool

    public init(
        id: String,
        name: String,
        bodyProtobuf: Data,
        bodyPlaintext: String,
        folderName: String,
        folderPath: String,
        accountName: String? = nil,
        snippet: String? = nil,
        creationDate: Date,
        modificationDate: Date,
        isLocked: Bool
    ) {
        self.id = id
        self.name = name
        self.bodyProtobuf = bodyProtobuf
        self.bodyPlaintext = bodyPlaintext
        self.folderName = folderName
        self.folderPath = folderPath
        self.accountName = accountName
        self.snippet = snippet
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isLocked = isLocked
    }
}

/// Raw folder data from Apple Notes before processing into our Folder model.
public struct AppleFolderRaw: Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var parentPath: String?

    public init(
        id: String,
        name: String,
        path: String,
        parentPath: String?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.parentPath = parentPath
    }
}
