import Foundation
import GRDB

public struct Note: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var bodyPlaintext: String
    public var folderPath: String
    public var accountName: String?
    public var snippet: String?
    public var creationDate: Date
    public var modificationDate: Date
    public var isLocked: Bool

    public init(
        id: String,
        title: String,
        bodyPlaintext: String,
        folderPath: String,
        accountName: String? = nil,
        snippet: String? = nil,
        creationDate: Date = Date(),
        modificationDate: Date = Date(),
        isLocked: Bool = false
    ) {
        self.id = id
        self.title = title
        self.bodyPlaintext = bodyPlaintext
        self.folderPath = folderPath
        self.accountName = accountName
        self.snippet = snippet
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isLocked = isLocked
    }

    public init(from raw: AppleNoteRaw) {
        self.init(
            id: raw.id,
            title: raw.name,
            bodyPlaintext: raw.bodyPlaintext,
            folderPath: raw.folderPath,
            accountName: raw.accountName,
            snippet: raw.snippet,
            creationDate: raw.creationDate,
            modificationDate: raw.modificationDate,
            isLocked: raw.isLocked
        )
    }
}

extension Note: FetchableRecord {}
