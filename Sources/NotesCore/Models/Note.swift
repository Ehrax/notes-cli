import CryptoKit
import Foundation
import GRDB

public struct Note: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var bodyProtobuf: Data
    public var bodyPlaintext: String
    public var folderPath: String
    public var accountName: String?
    public var snippet: String?
    public var creationDate: Date
    public var modificationDate: Date
    public var isLocked: Bool
    public var checksum: String
    public var syncedAt: Date

    public init(
        id: String,
        title: String,
        bodyProtobuf: Data,
        bodyPlaintext: String,
        folderPath: String,
        accountName: String? = nil,
        snippet: String? = nil,
        creationDate: Date = Date(),
        modificationDate: Date = Date(),
        isLocked: Bool = false,
        checksum: String? = nil,
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.bodyProtobuf = bodyProtobuf
        self.bodyPlaintext = bodyPlaintext
        self.folderPath = folderPath
        self.accountName = accountName
        self.snippet = snippet
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isLocked = isLocked
        self.checksum = checksum ?? Note.computeChecksum(bodyProtobuf)
        self.syncedAt = syncedAt
    }

    public init(from raw: AppleNoteRaw, syncedAt: Date = Date()) {
        self.init(
            id: raw.id,
            title: raw.name,
            bodyProtobuf: raw.bodyProtobuf,
            bodyPlaintext: raw.bodyPlaintext,
            folderPath: raw.folderPath,
            accountName: raw.accountName,
            snippet: raw.snippet,
            creationDate: raw.creationDate,
            modificationDate: raw.modificationDate,
            isLocked: raw.isLocked,
            syncedAt: syncedAt
        )
    }

    public static func computeChecksum(_ body: Data) -> String {
        let digest = SHA256.hash(data: body)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension Note: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "note"
}
