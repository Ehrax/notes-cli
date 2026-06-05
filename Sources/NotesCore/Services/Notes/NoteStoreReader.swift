import Foundation
import GRDB

// MARK: - NoteStoreReader

/// Reads the live NoteStore.sqlite read-only, no copy.
///
/// Opens Apple's `NoteStore.sqlite` directly with a read-only connection (no file copy,
/// cache, or mirror) and queries accounts, folders, notes, and attachments. Note bodies
/// are decoded from gzipped protobuf via ProtobufToMarkdown.
///
/// This is the fast read path (SQLite + protobuf). Writes go through ScriptingBridge.
public final class NoteStoreReader: Sendable {

    // MARK: - Constants

    private static let noteStoreRelativePath =
        "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"

    // MARK: - Properties

    /// Optional override for the database path (test seam for the error path).
    /// When nil, the live `sourceDBPath()` is opened.
    private let databasePath: String?

    // MARK: - Init

    public init(databasePath: String? = nil) {
        self.databasePath = databasePath
    }

    // MARK: - Public API

    /// Returns true if the source NoteStore.sqlite exists and appears readable.
    public func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: sourceDBPath())
    }

    /// Fetch all account names from the live NoteStore.
    public func fetchAccountNames() throws -> [String] {
        let db = try openDB()
        return try db.read { conn in
            let entityTypes = try requiredEntityTypes(conn, names: ["ICAccount"])
            let accountEnt = try entityType(named: "ICAccount", in: entityTypes)
            return try Row.fetchAll(
                conn,
                sql: "SELECT zname FROM ziccloudsyncingobject WHERE z_ent = ?",
                arguments: [accountEnt]
            ).compactMap { $0[0] as String? }
        }
    }

    /// Fetch the first account name (the default account).
    public func fetchDefaultAccountName() throws -> String? {
        try fetchAccountNames().first
    }

    /// Fetch all non-trash folders with resolved paths.
    public func fetchFolders() throws -> [AppleFolderRaw] {
        let db = try openDB()
        return try db.read { conn in
            let entityTypes = try requiredEntityTypes(conn, names: ["ICFolder", "ICAccount"])
            let folderEnt = try entityType(named: "ICFolder", in: entityTypes)
            let accountEnt = try entityType(named: "ICAccount", in: entityTypes)
            let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)
            let rawFolders = try queryFolders(conn, folderEnt: folderEnt)
            return buildAppleFolderRaws(rawFolders, accounts: accounts)
        }
    }

    /// Fetch metadata for all notes (no body decoding).
    public func fetchAllNoteMetadata() throws -> [AppleNoteMetadata] {
        let db = try openDB()
        return try db.read { conn in
            guard let context = try makeNoteReadContext(conn) else { return [] }
            let rows = try queryNoteRows(conn, noteEnt: context.noteEnt, validFolderPKs: context.validFolderPKs)

            return rows.compactMap { row -> AppleNoteMetadata? in
                guard let identifier = row.identifier,
                      let title = row.title,
                      let folderPK = row.folderPK else { return nil }
                let folderInfo = context.folderIndex[folderPK]
                return AppleNoteMetadata(
                    id: context.noteID(pk: row.pk, fallback: identifier),
                    name: title,
                    folderName: folderInfo?.name ?? "",
                    folderPath: folderInfo?.path ?? "",
                    accountName: context.accountName(folderPK: folderPK),
                    creationDate: row.creationDate ?? Date(),
                    modificationDate: row.modificationDate ?? Date(),
                    isLocked: row.isLocked
                )
            }
        }
    }

    /// Fetch all notes with decoded Markdown bodies.
    public func fetchAllNotes() throws -> [AppleNoteRaw] {
        let db = try openDB()
        return try db.read { conn in
            try fetchNotesInConnection(conn)
        }
    }

    /// Render a note body to Markdown, resolving inline attachments in one read transaction.
    public func renderMarkdownBody(for note: AppleNoteRaw) throws -> String {
        guard !note.bodyProtobuf.isEmpty else {
            return note.bodyPlaintext
        }

        let db = try openDB()
        return try db.read { conn in
            let resolver = ConnectionAttachmentResolver(conn: conn)
            return NoteBodyRenderer.markdown(for: note, resolver: resolver)
        }
    }

    /// Fetch a single note by its Apple identifier (ZIDENTIFIER).
    public func fetchNote(id: String) throws -> AppleNoteRaw? {
        let db = try openDB()
        return try db.read { conn in
            guard let context = try makeNoteReadContext(conn) else { return nil }
            // Resolve by Z_PK parsed from the x-coredata id; fall back to ZIDENTIFIER.
            let rows: [NoteRow]
            if let pk = notePK(fromScriptingID: id) {
                rows = try queryNoteRows(conn, noteEnt: context.noteEnt, validFolderPKs: context.validFolderPKs, pk: pk)
            } else {
                rows = try queryNoteRows(
                    conn, noteEnt: context.noteEnt, validFolderPKs: context.validFolderPKs, identifier: id
                )
            }

            guard let row = rows.first,
                  let title = row.title,
                  let folderPK = row.folderPK else { return nil }

            return try buildAppleNoteRaw(
                row: row,
                id: context.noteID(pk: row.pk, fallback: row.identifier ?? id),
                title: title,
                folderPK: folderPK,
                context: context,
                conn: conn
            )
        }
    }

    /// Fetch all attachments for a note (by Apple note ZIDENTIFIER).
    public func fetchAttachments(noteID: String) throws -> [NoteAttachment] {
        let db = try openDB()
        return try db.read { conn in
            let entityTypes = try requiredEntityTypes(
                conn, names: ["ICNote", "ICAttachment", "ICMedia", "ICAccount"]
            )
            let noteEnt = try entityType(named: "ICNote", in: entityTypes)
            let attachEnt = try entityType(named: "ICAttachment", in: entityTypes)
            let mediaEnt = try entityType(named: "ICMedia", in: entityTypes)
            let accountEnt = try entityType(named: "ICAccount", in: entityTypes)

            let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)

            // Prefer the Z_PK parsed from the x-coredata id; fall back to a ZIDENTIFIER lookup.
            let resolvedPK: Int
            if let pk = notePK(fromScriptingID: noteID) {
                resolvedPK = pk
            } else {
                let notePKRows = try Row.fetchAll(
                    conn,
                    sql: "SELECT z_pk FROM ziccloudsyncingobject WHERE z_ent = ? AND zidentifier = ?",
                    arguments: [noteEnt, noteID]
                )
                guard let pk = (notePKRows.first?[0] as Int64?).map({ Int($0) }) else { return [] }
                resolvedPK = pk
            }

            let acctUUID = try resolveAccountUUIDForNote(
                notePK: resolvedPK, accounts: accounts, conn: conn
            )

            return try queryAttachments(
                conn: conn,
                noteID: noteID,
                notePK: resolvedPK,
                acctUUID: acctUUID,
                attachEnt: attachEnt,
                mediaEnt: mediaEnt
            )
        }
    }
}

// MARK: - Private: Database

extension NoteStoreReader {
    func sourceDBPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/\(NoteStoreReader.noteStoreRelativePath)"
    }

    func openDB() throws -> DatabaseQueue {
        let path = databasePath ?? sourceDBPath()
        var config = Configuration()
        // R1: read-only + busy-timeout (NOT immutable=1) so we see our own future
        // writes via the -wal file rather than a stale checkpointed snapshot.
        config.readonly = true
        config.busyMode = .timeout(5)
        do {
            return try DatabaseQueue(path: path, configuration: config)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain
            && (error.code == EPERM || error.code == EACCES) {
            throw NotesError.commandFailed(message: Self.fullDiskAccessMessage)
        } catch {
            throw NotesError.databaseCorrupted(underlying: error)
        }
    }

    static let fullDiskAccessMessage = """
        Cannot access Apple Notes database — permission denied.

        notes-cli reads Apple Notes directly via SQLite (no AppleScript).
        This requires Full Disk Access for your terminal app.

        To fix, add one of these to Full Disk Access:
          • Your terminal app (Terminal, iTerm, Ghostty, etc.), OR
          • The notes-cli binary itself (/usr/local/bin/notes-cli)

        Steps:
          1. Open System Settings → Privacy & Security → Full Disk Access
          2. Click + and add the app/binary
          3. Restart your terminal (if you added the terminal app)
          4. Run a notes-cli read command again

        Or open the settings pane directly:
          open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        """
}

// MARK: - Private: Scripting identifiers

extension NoteStoreReader {
    /// The Core Data store UUID (Z_METADATA.Z_UUID). Combined with a note's Z_PK it
    /// reconstructs the `x-coredata://<uuid>/ICNote/p<pk>` id that ScriptingBridge uses
    /// to address a note — verified equal to `id of note`.
    func fetchStoreUUID(_ db: Database) -> String? {
        try? String.fetchOne(db, sql: "SELECT Z_UUID FROM Z_METADATA LIMIT 1")
    }

    /// Extract the note Z_PK from an `x-coredata://…/ICNote/p<pk>` id, if present.
    func notePK(fromScriptingID id: String) -> Int? {
        guard let range = id.range(of: "/ICNote/p") else { return nil }
        return Int(id[range.upperBound...].prefix { $0.isNumber })
    }
}

// MARK: - Private: Entity Types

private extension NoteStoreReader {
    /// Query Z_PRIMARYKEY to build a map of entity name → Z_ENT integer.
    func loadEntityTypes(_ db: Database) throws -> [String: Int64] {
        var result: [String: Int64] = [:]
        let rows = try Row.fetchAll(db, sql: "SELECT z_ent, z_name FROM z_primarykey")
        for row in rows {
            if let ent = row[0] as Int64?, let name = row[1] as String? {
                result[name] = ent
            }
        }
        return result
    }

    func requiredEntityTypes(_ db: Database, names: [String]) throws -> [String: Int64] {
        let entityTypes = try loadEntityTypes(db)
        let missing = names.filter { entityTypes[$0] == nil }
        guard missing.isEmpty else {
            throw NotesError.unsupportedNoteStoreSchema(missingEntities: missing)
        }
        return entityTypes
    }

    func entityType(named name: String, in entityTypes: [String: Int64]) throws -> Int64 {
        guard let value = entityTypes[name] else {
            throw NotesError.unsupportedNoteStoreSchema(missingEntities: [name])
        }
        return value
    }
}

// MARK: - Private: Accounts

extension NoteStoreReader {
    struct AccountInfo {
        let pk: Int
        let name: String
        let identifier: String
    }

    /// Returns a map of Z_PK → AccountInfo for all ICAccount entities.
    func fetchAccountsMap(_ db: Database, accountEnt: Int64) throws -> [Int: AccountInfo] {
        var result: [Int: AccountInfo] = [:]
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT z_pk, zname, zidentifier FROM ziccloudsyncingobject WHERE z_ent = ?",
            arguments: [accountEnt]
        )
        for row in rows {
            guard let pk = (row[0] as Int64?).map({ Int($0) }),
                  let name = row[1] as String? else { continue }
            let identifier = row[2] as String? ?? ""
            result[pk] = AccountInfo(pk: pk, name: name, identifier: identifier)
        }
        return result
    }
}

// MARK: - Private: Folders

private extension NoteStoreReader {
    struct RawFolderRow {
        let pk: Int
        let title: String?
        let identifier: String?
        let parentPK: Int?
        let ownerPK: Int?
        let folderType: Int64
    }

    struct FolderInfo {
        let name: String
        let path: String
    }

    /// Query non-trash folders (foldertype 1 is trash).
    func queryFolders(_ db: Database, folderEnt: Int64) throws -> [RawFolderRow] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT z_pk, ztitle2, zidentifier, zparent, zowner, zfoldertype
                FROM ziccloudsyncingobject
                WHERE z_ent = ? AND (zfoldertype IS NULL OR zfoldertype = 0)
                  AND (zmarkedfordeletion IS NULL OR zmarkedfordeletion = 0)
                """,
            arguments: [folderEnt]
        )
        return rows.compactMap { row -> RawFolderRow? in
            guard let pk = (row[0] as Int64?).map({ Int($0) }) else { return nil }
            return RawFolderRow(
                pk: pk,
                title: row[1] as String?,
                identifier: row[2] as String?,
                parentPK: (row[3] as Int64?).map({ Int($0) }),
                ownerPK: (row[4] as Int64?).map({ Int($0) }),
                folderType: row[5] as Int64? ?? 0
            )
        }
    }

    /// Build a PK → FolderInfo index with fully-resolved folder paths.
    ///
    /// Root-level folders (no parent in our set) are prefixed with the account name,
    /// matching Apple Notes' account-prefixed path format (e.g., "iCloud/My Folder/Subfolder").
    func buildFolderIndex(
        _ rawFolders: [RawFolderRow],
        accounts: [Int: AccountInfo]
    ) -> [Int: FolderInfo] {
        let byPK = Dictionary(uniqueKeysWithValues: rawFolders.map { ($0.pk, $0) })
        var cache: [Int: FolderInfo] = [:]

        func resolve(_ pk: Int) -> FolderInfo? {
            if let cached = cache[pk] { return cached }
            guard let folder = byPK[pk] else { return nil }
            let name = folder.title ?? "Untitled"

            if let parentPK = folder.parentPK, byPK[parentPK] != nil {
                if let parentInfo = resolve(parentPK) {
                    let info = FolderInfo(name: name, path: "\(parentInfo.path)/\(name)")
                    cache[pk] = info
                    return info
                }
            }

            // Root-level folder: prefix with account name
            let prefix: String
            if let ownerPK = folder.ownerPK, let acct = accounts[ownerPK] {
                prefix = acct.name
            } else {
                prefix = ""
            }
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            let info = FolderInfo(name: name, path: path)
            cache[pk] = info
            return info
        }

        for folder in rawFolders {
            _ = resolve(folder.pk)
        }
        return cache
    }

    /// Build AppleFolderRaw values with resolved paths.
    func buildAppleFolderRaws(
        _ rawFolders: [RawFolderRow],
        accounts: [Int: AccountInfo]
    ) -> [AppleFolderRaw] {
        let index = buildFolderIndex(rawFolders, accounts: accounts)

        // Deduplicate by path to prevent UNIQUE constraint violations
        var seenPaths = Set<String>()
        return rawFolders.compactMap { folder -> AppleFolderRaw? in
            guard let identifier = folder.identifier,
                  let info = index[folder.pk],
                  !info.path.isEmpty,
                  seenPaths.insert(info.path).inserted else { return nil }

            var parentPath: String?
            if let parentPK = folder.parentPK, let parentInfo = index[parentPK] {
                parentPath = parentInfo.path
            } else if let ownerPK = folder.ownerPK, let acct = accounts[ownerPK] {
                parentPath = acct.name
            }

            return AppleFolderRaw(
                id: identifier,
                name: info.name,
                path: info.path,
                parentPath: parentPath
            )
        }
    }

}

// MARK: - Private: Notes

private extension NoteStoreReader {
    struct NoteRow {
        let pk: Int
        let identifier: String?
        let title: String?
        let folderPK: Int?
        let creationDate: Date?
        let modificationDate: Date?
        let isLocked: Bool
        let snippet: String?
    }

    struct NoteReadContext {
        let storeUUID: String?
        let noteEnt: Int64
        let accounts: [Int: AccountInfo]
        let folderIndex: [Int: FolderInfo]
        let byFolderPK: [Int: RawFolderRow]
        let validFolderPKs: Set<Int>

        func noteID(pk: Int, fallback: String) -> String {
            guard let storeUUID, !storeUUID.isEmpty else { return fallback }
            return "x-coredata://\(storeUUID)/ICNote/p\(pk)"
        }

        func accountName(folderPK: Int) -> String? {
            var current = byFolderPK[folderPK]
            while let folder = current {
                if let ownerPK = folder.ownerPK, let acct = accounts[ownerPK] {
                    return acct.name
                }
                if let parentPK = folder.parentPK {
                    current = byFolderPK[parentPK]
                } else {
                    break
                }
            }
            return nil
        }
    }

    func makeNoteReadContext(_ conn: Database) throws -> NoteReadContext? {
        let entityTypes = try requiredEntityTypes(conn, names: ["ICNote", "ICFolder", "ICAccount"])
        let noteEnt = try entityType(named: "ICNote", in: entityTypes)
        let folderEnt = try entityType(named: "ICFolder", in: entityTypes)
        let accountEnt = try entityType(named: "ICAccount", in: entityTypes)

        let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)
        let rawFolders = try queryFolders(conn, folderEnt: folderEnt)
        return NoteReadContext(
            storeUUID: fetchStoreUUID(conn),
            noteEnt: noteEnt,
            accounts: accounts,
            folderIndex: buildFolderIndex(rawFolders, accounts: accounts),
            byFolderPK: Dictionary(uniqueKeysWithValues: rawFolders.map { ($0.pk, $0) }),
            validFolderPKs: Set(rawFolders.map { $0.pk })
        )
    }

    /// Query note rows, excluding notes in folders not present in validFolderPKs.
    /// Pass `identifier` to restrict to a single note by ZIDENTIFIER (uses SQL index).
    func queryNoteRows(
        _ db: Database,
        noteEnt: Int64,
        validFolderPKs: Set<Int>,
        identifier: String? = nil,
        pk: Int? = nil
    ) throws -> [NoteRow] {
        // Use NULL-column compatibility trick for columns that may not exist on older macOS
        var filterClause = ""
        if identifier != nil { filterClause += " AND zidentifier = ?" }
        if pk != nil { filterClause += " AND z_pk = ?" }
        let sql = """
            SELECT z_pk, zidentifier, ztitle1, zfolder,
                   COALESCE(zcreationdate1, zcreationdate2, zcreationdate3, zmodificationdate1),
                   zmodificationdate1, zispasswordprotected, zsnippet
            FROM (
                SELECT *, NULL AS zispasswordprotected, NULL AS zsnippet,
                       NULL AS zcreationdate2, NULL AS zcreationdate3
                FROM ziccloudsyncingobject
            )
            WHERE z_ent = ? AND ztitle1 IS NOT NULL
              AND (zmarkedfordeletion IS NULL OR zmarkedfordeletion = 0) \(filterClause)
            """
        var arguments: StatementArguments = [noteEnt]
        if let identifier {
            arguments += [identifier]
        }
        if let pk {
            arguments += [pk]
        }
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        return rows.compactMap { row -> NoteRow? in
            guard let pk = (row[0] as Int64?).map({ Int($0) }) else { return nil }
            let folderPK = (row[3] as Int64?).map({ Int($0) })

            // Exclude notes whose folder is trash / not in our non-trash set
            if let fPK = folderPK, !validFolderPKs.contains(fPK) { return nil }

            let creationDate = (row[4] as Double?).map { Date(timeIntervalSinceReferenceDate: $0) }
            let modDate = (row[5] as Double?).map { Date(timeIntervalSinceReferenceDate: $0) }
            let isLocked = (row[6] as Int64? ?? 0) != 0

            return NoteRow(
                pk: pk,
                identifier: row[1] as String?,
                title: row[2] as String?,
                folderPK: folderPK,
                creationDate: creationDate,
                modificationDate: modDate,
                isLocked: isLocked,
                snippet: row[7] as String?
            )
        }
    }

    func fetchNotesInConnection(_ conn: Database) throws -> [AppleNoteRaw] {
        guard let context = try makeNoteReadContext(conn) else { return [] }
        let rows = try queryNoteRows(conn, noteEnt: context.noteEnt, validFolderPKs: context.validFolderPKs)

        return try rows.compactMap { row -> AppleNoteRaw? in
            guard let title = row.title,
                  let folderPK = row.folderPK else { return nil }
            return try buildAppleNoteRaw(
                row: row,
                id: context.noteID(pk: row.pk, fallback: row.identifier ?? ""),
                title: title,
                folderPK: folderPK,
                context: context,
                conn: conn
            )
        }
    }

    func buildAppleNoteRaw(
        row: NoteRow,
        id: String,
        title: String,
        folderPK: Int,
        context: NoteReadContext,
        conn: Database
    ) throws -> AppleNoteRaw {
        let folderInfo = context.folderIndex[folderPK]
        let acctName = context.accountName(folderPK: folderPK)

        // Locked notes: store metadata only, body is empty
        guard !row.isLocked else {
            return AppleNoteRaw(
                id: id,
                name: title,
                bodyProtobuf: Data(),
                bodyPlaintext: "",
                folderName: folderInfo?.name ?? "",
                folderPath: folderInfo?.path ?? "",
                accountName: acctName,
                snippet: row.snippet,
                creationDate: row.creationDate ?? Date(),
                modificationDate: row.modificationDate ?? Date(),
                isLocked: true
            )
        }

        let (body, plaintext) = decodeNoteBody(notePK: row.pk, conn: conn, noteID: id)

        return AppleNoteRaw(
            id: id,
            name: title,
            bodyProtobuf: body,
            bodyPlaintext: plaintext,
            folderName: folderInfo?.name ?? "",
            folderPath: folderInfo?.path ?? "",
            accountName: acctName,
            snippet: row.snippet,
            creationDate: row.creationDate ?? Date(),
            modificationDate: row.modificationDate ?? Date(),
            isLocked: false
        )
    }

    /// Decode the gzipped protobuf body for a note. Returns (raw ZDATA blob, plaintext).
    /// On failure, logs a warning and returns empty data/string.
    func decodeNoteBody(notePK: Int, conn: Database, noteID: String) -> (Data, String) {
        do {
            let blobRows = try Row.fetchAll(
                conn,
                sql: "SELECT zdata FROM zicnotedata WHERE znote = ?",
                arguments: [Int64(notePK)]
            )
            guard let blobRow = blobRows.first,
                  let data = blobRow[0] as Data? else {
                return (Data(), "")
            }
            let plaintext = try ProtobufToMarkdown.plaintext(from: data)
            return (data, plaintext)
        } catch {
            Log.info(
                "Failed to decode note body for \(noteID): \(error.localizedDescription)",
                logger: Log.general
            )
            return (Data(), "")
        }
    }
}
