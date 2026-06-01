import Foundation
import GRDB

// MARK: - NoteStoreReader

/// Reads Apple Notes data directly from NoteStore.sqlite.
///
/// Copies the database to ~/.notes-cli/cache/ for safe read-only access, then queries
/// accounts, folders, notes, and attachments. Note bodies are decoded from gzipped
/// protobuf via ProtobufToMarkdown.
///
/// This is the fast read path (SQLite + protobuf), replacing the AppleScript read path.
/// Write operations remain in AppleScriptWriter.
public final class NoteStoreReader: Sendable {

    // MARK: - Constants

    private static let noteStoreRelativePath =
        "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"

    private static let fileSuffixes = ["", "-shm", "-wal"]

    // MARK: - Properties

    private let cacheDir: String

    // MARK: - Init

    public init(cacheDir: String) {
        self.cacheDir = cacheDir
    }

    // MARK: - Public API

    /// Copy NoteStore.sqlite (+ -shm, -wal) to the cache directory and verify it opens.
    ///
    /// Must be called before any fetch methods. Safe to call multiple times (re-copies on each call).
    public func refresh() throws {
        let source = sourceDBPath()
        let dest = cachedDBPath()

        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDir) {
            do {
                try fm.createDirectory(
                    at: URL(fileURLWithPath: cacheDir),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw NotesError.commandFailed(
                    message: "Cannot create cache directory: \(error.localizedDescription)"
                )
            }
        }

        for suffix in Self.fileSuffixes {
            let srcPath = source + suffix
            let dstPath = dest + suffix
            guard fm.fileExists(atPath: srcPath) else {
                if suffix.isEmpty {
                    throw NotesError.commandFailed(
                        message: "Apple Notes database not found at \(srcPath)."
                    )
                }
                // -shm / -wal may not exist when WAL is checkpointed — skip silently
                continue
            }
            do {
                if fm.fileExists(atPath: dstPath) {
                    try fm.removeItem(atPath: dstPath)
                }
                try fm.copyItem(atPath: srcPath, toPath: dstPath)
            } catch let error as NSError {
                if error.domain == NSPOSIXErrorDomain && (error.code == EPERM || error.code == EACCES) {
                    throw NotesError.commandFailed(
                        message: """
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
                          4. Run `notes-cli sync` again

                        Or open the settings pane directly:
                          open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                        """
                    )
                }
                throw NotesError.commandFailed(
                    message: "Failed to copy NoteStore.sqlite: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Returns true if the source NoteStore.sqlite exists and appears readable.
    public func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: sourceDBPath())
    }

    /// Fetch all account names from the cache.
    public func fetchAccountNames() throws -> [String] {
        let db = try openDB()
        return try db.read { conn in
            let entityTypes = try loadEntityTypes(conn)
            guard let accountEnt = entityTypes["ICAccount"] else { return [] }
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
            let entityTypes = try loadEntityTypes(conn)
            guard let folderEnt = entityTypes["ICFolder"],
                  let accountEnt = entityTypes["ICAccount"] else { return [] }
            let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)
            let rawFolders = try queryFolders(conn, folderEnt: folderEnt)
            return buildAppleFolderRaws(rawFolders, accounts: accounts)
        }
    }

    /// Fetch metadata for all notes (no body decoding).
    public func fetchAllNoteMetadata() throws -> [AppleNoteMetadata] {
        let db = try openDB()
        return try db.read { conn in
            let entityTypes = try loadEntityTypes(conn)
            guard let noteEnt = entityTypes["ICNote"],
                  let folderEnt = entityTypes["ICFolder"],
                  let accountEnt = entityTypes["ICAccount"] else { return [] }

            let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)
            let rawFolders = try queryFolders(conn, folderEnt: folderEnt)
            let folderIndex = buildFolderIndex(rawFolders, accounts: accounts)
            let byPK = Dictionary(uniqueKeysWithValues: rawFolders.map { ($0.pk, $0) })
            let validFolderPKs = Set(rawFolders.map { $0.pk })
            let rows = try queryNoteRows(conn, noteEnt: noteEnt, validFolderPKs: validFolderPKs)

            return rows.compactMap { row -> AppleNoteMetadata? in
                guard let identifier = row.identifier,
                      let title = row.title,
                      let folderPK = row.folderPK else { return nil }
                let folderInfo = folderIndex[folderPK]
                return AppleNoteMetadata(
                    id: identifier,
                    name: title,
                    folderName: folderInfo?.name ?? "",
                    folderPath: folderInfo?.path ?? "",
                    accountName: resolveAccountName(
                        folderPK: folderPK,
                        byPK: byPK,
                        accounts: accounts
                    ),
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

    /// Fetch a single note by its Apple identifier (ZIDENTIFIER).
    public func fetchNote(id: String) throws -> AppleNoteRaw? {
        let db = try openDB()
        return try db.read { conn in
            let entityTypes = try loadEntityTypes(conn)
            guard let noteEnt = entityTypes["ICNote"],
                  let folderEnt = entityTypes["ICFolder"],
                  let accountEnt = entityTypes["ICAccount"] else { return nil }

            let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)
            let rawFolders = try queryFolders(conn, folderEnt: folderEnt)
            let folderIndex = buildFolderIndex(rawFolders, accounts: accounts)
            let byPK = Dictionary(uniqueKeysWithValues: rawFolders.map { ($0.pk, $0) })
            let validFolderPKs = Set(rawFolders.map { $0.pk })
            // Filter by identifier in SQL to avoid loading all notes
            let rows = try queryNoteRows(conn, noteEnt: noteEnt, validFolderPKs: validFolderPKs, identifier: id)

            guard let row = rows.first,
                  let identifier = row.identifier,
                  let title = row.title,
                  let folderPK = row.folderPK else { return nil }

            return try buildAppleNoteRaw(
                row: row,
                identifier: identifier,
                title: title,
                folderPK: folderPK,
                folderIndex: folderIndex,
                byPK: byPK,
                accounts: accounts,
                conn: conn
            )
        }
    }

    /// Fetch all attachments for a note (by Apple note ZIDENTIFIER).
    public func fetchAttachments(noteID: String) throws -> [NoteAttachment] {
        let db = try openDB()
        return try db.read { conn in
            let entityTypes = try loadEntityTypes(conn)
            guard let noteEnt = entityTypes["ICNote"],
                  let attachEnt = entityTypes["ICAttachment"],
                  let mediaEnt = entityTypes["ICMedia"],
                  let accountEnt = entityTypes["ICAccount"] else { return [] }

            let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)

            // Find the note's Z_PK from its ZIDENTIFIER
            let notePKRows = try Row.fetchAll(
                conn,
                sql: "SELECT z_pk FROM ziccloudsyncingobject WHERE z_ent = ? AND zidentifier = ?",
                arguments: [noteEnt, noteID]
            )
            guard let notePKRow = notePKRows.first,
                  let notePK = (notePKRow[0] as Int64?).map({ Int($0) }) else { return [] }

            let acctUUID = try resolveAccountUUIDForNote(
                notePK: notePK, accounts: accounts, conn: conn
            )

            return try queryAttachments(
                conn: conn,
                noteID: noteID,
                notePK: notePK,
                acctUUID: acctUUID,
                attachEnt: attachEnt,
                mediaEnt: mediaEnt
            )
        }
    }
}

// MARK: - Private: Database

private extension NoteStoreReader {
    func sourceDBPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/\(NoteStoreReader.noteStoreRelativePath)"
    }

    func cachedDBPath() -> String {
        "\(cacheDir)/NoteStore.sqlite"
    }

    func openDB() throws -> DatabaseQueue {
        let path = cachedDBPath()
        guard FileManager.default.fileExists(atPath: path) else {
            throw NotesError.commandFailed(
                message: "NoteStore cache not found. Call refresh() first."
            )
        }
        var config = Configuration()
        config.readonly = true
        do {
            return try DatabaseQueue(path: path, configuration: config)
        } catch {
            throw NotesError.databaseCorrupted(underlying: error)
        }
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
}

// MARK: - Private: Accounts

private extension NoteStoreReader {
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
    /// matching the path format AppleScript returns (e.g., "iCloud/My Folder/Subfolder").
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

    /// Walk folder hierarchy to find the account name for a given folder PK.
    /// `byPK` must be pre-built from the same rawFolders array to avoid repeated allocation.
    func resolveAccountName(
        folderPK: Int,
        byPK: [Int: RawFolderRow],
        accounts: [Int: AccountInfo]
    ) -> String? {
        var current = byPK[folderPK]
        while let folder = current {
            if let ownerPK = folder.ownerPK, let acct = accounts[ownerPK] {
                return acct.name
            }
            if let parentPK = folder.parentPK {
                current = byPK[parentPK]
            } else {
                break
            }
        }
        return nil
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

    /// Query note rows, excluding notes in folders not present in validFolderPKs.
    /// Pass `identifier` to restrict to a single note by ZIDENTIFIER (uses SQL index).
    func queryNoteRows(
        _ db: Database,
        noteEnt: Int64,
        validFolderPKs: Set<Int>,
        identifier: String? = nil
    ) throws -> [NoteRow] {
        // Use NULL-column compatibility trick for columns that may not exist on older macOS
        let identifierClause = identifier != nil ? "AND zidentifier = ?" : ""
        let sql = """
            SELECT z_pk, zidentifier, ztitle1, zfolder,
                   COALESCE(zcreationdate1, zcreationdate2, zcreationdate3, zmodificationdate1),
                   zmodificationdate1, zispasswordprotected, zsnippet
            FROM (
                SELECT *, NULL AS zispasswordprotected, NULL AS zsnippet,
                       NULL AS zcreationdate2, NULL AS zcreationdate3
                FROM ziccloudsyncingobject
            )
            WHERE z_ent = ? AND ztitle1 IS NOT NULL \(identifierClause)
            """
        var arguments: StatementArguments = [noteEnt]
        if let identifier {
            arguments += [identifier]
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
        let entityTypes = try loadEntityTypes(conn)
        guard let noteEnt = entityTypes["ICNote"],
              let folderEnt = entityTypes["ICFolder"],
              let accountEnt = entityTypes["ICAccount"] else { return [] }

        let accounts = try fetchAccountsMap(conn, accountEnt: accountEnt)
        let rawFolders = try queryFolders(conn, folderEnt: folderEnt)
        let folderIndex = buildFolderIndex(rawFolders, accounts: accounts)
        let byPK = Dictionary(uniqueKeysWithValues: rawFolders.map { ($0.pk, $0) })
        let validFolderPKs = Set(rawFolders.map { $0.pk })
        let rows = try queryNoteRows(conn, noteEnt: noteEnt, validFolderPKs: validFolderPKs)

        return try rows.compactMap { row -> AppleNoteRaw? in
            guard let identifier = row.identifier,
                  let title = row.title,
                  let folderPK = row.folderPK else { return nil }
            return try buildAppleNoteRaw(
                row: row,
                identifier: identifier,
                title: title,
                folderPK: folderPK,
                folderIndex: folderIndex,
                byPK: byPK,
                accounts: accounts,
                conn: conn
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    func buildAppleNoteRaw(
        row: NoteRow,
        identifier: String,
        title: String,
        folderPK: Int,
        folderIndex: [Int: FolderInfo],
        byPK: [Int: RawFolderRow],
        accounts: [Int: AccountInfo],
        conn: Database
    ) throws -> AppleNoteRaw {
        let folderInfo = folderIndex[folderPK]
        let acctName = resolveAccountName(folderPK: folderPK, byPK: byPK, accounts: accounts)

        // Locked notes: store metadata only, body is empty
        guard !row.isLocked else {
            return AppleNoteRaw(
                id: identifier,
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

        let (body, plaintext) = decodeNoteBody(notePK: row.pk, conn: conn, noteID: identifier)

        return AppleNoteRaw(
            id: identifier,
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
            let plaintext = ProtobufToMarkdown.extractPlaintext(from: data)
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

// MARK: - Private: Attachments

private extension NoteStoreReader {
    /// Find the account UUID for a given note Z_PK via zowner column.
    func resolveAccountUUIDForNote(
        notePK: Int,
        accounts: [Int: AccountInfo],
        conn: Database
    ) throws -> String? {
        // Notes don't have ZOWNER directly — they have ZFOLDER → folder has ZOWNER → account.
        let rows = try Row.fetchAll(
            conn,
            sql: """
                SELECT f.zowner FROM ziccloudsyncingobject n
                JOIN ziccloudsyncingobject f ON f.z_pk = n.zfolder
                WHERE n.z_pk = ?
                """,
            arguments: [Int64(notePK)]
        )
        if let ownerPK = (rows.first?[0] as Int64?).map({ Int($0) }) {
            return accounts[ownerPK]?.identifier
        }
        return nil
    }

    func queryAttachments(
        conn: Database,
        noteID: String,
        notePK: Int,
        acctUUID: String?,
        attachEnt: Int64,
        mediaEnt: Int64
    ) throws -> [NoteAttachment] {
        let rows = try Row.fetchAll(
            conn,
            sql: """
                SELECT zidentifier, ztypeuti, zmedia
                FROM ziccloudsyncingobject
                WHERE z_ent = ? AND znote = ?
                """,
            arguments: [attachEnt, Int64(notePK)]
        )

        return try rows.compactMap { row -> NoteAttachment? in
            guard let attachUUID = row[0] as String? else { return nil }
            let typeUTI = row[1] as String?
            let mediaPK = (row[2] as Int64?).map({ Int($0) })

            let (filename, relativePath) = try resolveMediaPath(
                attachUUID: attachUUID,
                mediaPK: mediaPK,
                acctUUID: acctUUID,
                mediaEnt: mediaEnt,
                conn: conn
            )

            return NoteAttachment(
                id: attachUUID,
                noteID: noteID,
                filename: filename,
                typeUTI: typeUTI,
                relativePath: relativePath
            )
        }
    }

    func resolveMediaPath(
        attachUUID: String,
        mediaPK: Int?,
        acctUUID: String?,
        mediaEnt: Int64,
        conn: Database
    ) throws -> (filename: String?, relativePath: String) {
        guard let mediaPK else {
            return (nil, "Attachments/\(attachUUID)")
        }

        let mediaRows = try Row.fetchAll(
            conn,
            sql: """
                SELECT zidentifier, zfilename, zgeneration1
                FROM (SELECT *, NULL AS zgeneration1 FROM ziccloudsyncingobject)
                WHERE z_ent = ? AND z_pk = ?
                """,
            arguments: [mediaEnt, Int64(mediaPK)]
        )

        guard let mediaRow = mediaRows.first else {
            return (nil, "Attachments/\(attachUUID)")
        }

        let mediaUUID = mediaRow[0] as String? ?? attachUUID
        let filename = mediaRow[1] as String?
        let generation = mediaRow[2] as String?

        let base: String
        if let acctUUID {
            base = "Accounts/\(acctUUID)/Media/\(mediaUUID)"
        } else {
            base = "Media/\(mediaUUID)"
        }

        let relativePath: String
        if let gen = generation, !gen.isEmpty, let file = filename {
            relativePath = "\(base)/\(gen)/\(file)"
        } else if let file = filename {
            relativePath = "\(base)/\(file)"
        } else {
            relativePath = base
        }

        return (filename, relativePath)
    }
}

// MARK: - AttachmentResolver

extension NoteStoreReader: AttachmentResolver {
    public func resolveInlineText(uuid: String) -> String? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            try String.fetchOne(
                conn,
                sql: "SELECT ZALTTEXT FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            )
        }
    }

    public func resolveTableData(uuid: String) -> Data? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            try Data.fetchOne(
                conn,
                sql: "SELECT ZMERGEABLEDATA1 FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            )
        }
    }

    public func resolveURLCard(uuid: String) -> (title: String, url: String)? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            let row = try Row.fetchOne(
                conn,
                sql: "SELECT ZTITLE, ZURLSTRING FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            )
            guard let row,
                  let title = row["ZTITLE"] as String?,
                  let url = row["ZURLSTRING"] as String? else { return nil }
            return (title: title, url: url)
        }
    }

    public func resolveInternalLink(uuid: String) -> String? {
        guard let db = try? openDB() else { return nil }
        return try? db.read { conn in
            // Step 1: Get the content identifier for this link attachment
            guard let noteIdentifier = try String.fetchOne(
                conn,
                sql: "SELECT ZTOKENCONTENTIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [uuid]
            ) else { return nil }

            // Step 2: Look up the linked note's title by its identifier
            return try String.fetchOne(
                conn,
                sql: "SELECT ZTITLE1 FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ?",
                arguments: [noteIdentifier]
            )
        }
    }
}
