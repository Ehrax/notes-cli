import Foundation
import GRDB
import Testing
@testable import NotesCore
import NotesTestSupport

@Suite("NoteStoreReader Tests")
struct NoteStoreReaderTests {

    /// Whether the real Apple Notes database is accessible (Full Disk Access granted).
    private var realDBAccessible: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
        return FileManager.default.isReadableFile(atPath: path)
    }

    /// A path that does not point at a readable SQLite database.
    private func bogusDBPath() -> String {
        "/tmp/notes-cli-test-nonexistent-\(UUID().uuidString)/NoteStore.sqlite"
    }

    private func databaseWithMissingEntities() throws -> URL {
        let directory = try makeTempDirectory(prefix: "notes-cli-schema")
        let url = directory.appendingPathComponent("NoteStore.sqlite")
        let db = try DatabaseQueue(path: url.path)
        try db.write { conn in
            try conn.execute(sql: "CREATE TABLE z_primarykey (z_ent INTEGER, z_name TEXT)")
        }
        return url
    }

    private func databaseWithUndecodableNoteBody() throws -> URL {
        let directory = try makeTempDirectory(prefix: "notes-cli-undecodable-body")
        let url = directory.appendingPathComponent("NoteStore.sqlite")
        let db = try DatabaseQueue(path: url.path)
        try db.write { conn in
            try conn.execute(sql: "CREATE TABLE z_metadata (z_uuid TEXT)")
            try conn.execute(sql: "INSERT INTO z_metadata (z_uuid) VALUES (?)", arguments: ["STORE"])
            try conn.execute(sql: "CREATE TABLE z_primarykey (z_ent INTEGER, z_name TEXT)")
            try conn.execute(sql: "INSERT INTO z_primarykey (z_ent, z_name) VALUES (1, 'ICAccount')")
            try conn.execute(sql: "INSERT INTO z_primarykey (z_ent, z_name) VALUES (2, 'ICFolder')")
            try conn.execute(sql: "INSERT INTO z_primarykey (z_ent, z_name) VALUES (3, 'ICNote')")
            try conn.execute(sql: """
                CREATE TABLE ziccloudsyncingobject (
                    z_pk INTEGER PRIMARY KEY,
                    z_ent INTEGER,
                    zname TEXT,
                    zidentifier TEXT,
                    ztitle2 TEXT,
                    zparent INTEGER,
                    zowner INTEGER,
                    zfoldertype INTEGER,
                    ztitle1 TEXT,
                    zfolder INTEGER,
                    zcreationdate1 REAL,
                    zcreationdate2 REAL,
                    zcreationdate3 REAL,
                    zmodificationdate1 REAL,
                    zispasswordprotected INTEGER,
                    zsnippet TEXT,
                    zmarkedfordeletion INTEGER
                )
                """)
            try conn.execute(
                sql: "INSERT INTO ziccloudsyncingobject (z_pk, z_ent, zname, zidentifier) VALUES (10, 1, 'iCloud', 'acct')"
            )
            try conn.execute(
                sql: """
                    INSERT INTO ziccloudsyncingobject
                    (z_pk, z_ent, zidentifier, ztitle2, zowner, zfoldertype, zmarkedfordeletion)
                    VALUES (20, 2, 'folder', 'Notes', 10, 0, 0)
                    """
            )
            try conn.execute(
                sql: """
                    INSERT INTO ziccloudsyncingobject
                    (z_pk, z_ent, zidentifier, ztitle1, zfolder, zcreationdate1, zmodificationdate1,
                     zispasswordprotected, zmarkedfordeletion)
                    VALUES (30, 3, 'note', 'Broken Body', 20, 0, 0, 0, 0)
                    """
            )
            try conn.execute(sql: "CREATE TABLE zicnotedata (znote INTEGER, zdata BLOB)")
            try conn.execute(
                sql: "INSERT INTO zicnotedata (znote, zdata) VALUES (?, ?)",
                arguments: [30, Data([0x62, 0x61, 0x64])]
            )
        }
        return url
    }

    // MARK: - isAvailable

    @Test("isAvailable returns false when NoteStore.sqlite does not exist")
    func isAvailableReturnsFalseForMissingDatabase() throws {
        // isAvailable() checks the live source path; only meaningful without Full Disk Access.
        guard !realDBAccessible else { return }

        let reader = NoteStoreReader()
        #expect(reader.isAvailable() == false)
    }

    // MARK: - Error path (unreadable live DB)

    @Test("fetchAccountNames throws NotesError when the DB path is unreadable")
    func fetchAccountNamesThrowsWhenUnreadable() throws {
        let reader = NoteStoreReader(databasePath: bogusDBPath())
        #expect(throws: (any Error).self) {
            try reader.fetchAccountNames()
        }
    }

    @Test("fetchFolders throws NotesError when the DB path is unreadable")
    func fetchFoldersThrowsWhenUnreadable() throws {
        let reader = NoteStoreReader(databasePath: bogusDBPath())
        #expect(throws: (any Error).self) {
            try reader.fetchFolders()
        }
    }

    @Test("fetchAllNotes throws NotesError when the DB path is unreadable")
    func fetchAllNotesThrowsWhenUnreadable() throws {
        let reader = NoteStoreReader(databasePath: bogusDBPath())
        #expect(throws: (any Error).self) {
            try reader.fetchAllNotes()
        }
    }

    @Test("fetchAttachments throws NotesError when the DB path is unreadable")
    func fetchAttachmentsThrowsWhenUnreadable() throws {
        let reader = NoteStoreReader(databasePath: bogusDBPath())
        #expect(throws: (any Error).self) {
            try reader.fetchAttachments(noteID: "test-note-id")
        }
    }

    @Test("fetchAllNotes throws when required NoteStore entities are missing")
    func fetchAllNotesThrowsForMissingEntities() throws {
        let url = try databaseWithMissingEntities()
        defer { removeTempDirectory(url.deletingLastPathComponent()) }
        let reader = NoteStoreReader(databasePath: url.path)

        #expect(throws: NotesError.self) {
            try reader.fetchAllNotes()
        }
    }

    @Test("fetchAllNotes keeps the raw body blob when plaintext decoding fails")
    func fetchAllNotesKeepsRawBodyWhenPlaintextDecodeFails() throws {
        let url = try databaseWithUndecodableNoteBody()
        defer { removeTempDirectory(url.deletingLastPathComponent()) }
        let reader = NoteStoreReader(databasePath: url.path)

        let note = try #require(reader.fetchAllNotes().first)

        #expect(note.name == "Broken Body")
        #expect(note.bodyProtobuf == Data([0x62, 0x61, 0x64]))
        #expect(note.bodyPlaintext == "")
    }

    // MARK: - Live read (no copy)

    @Test("live read works and creates no cache directory")
    func liveReadWorksAndCreatesNoCopy() throws {
        guard realDBAccessible else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cacheDir = "\(home)/.notes-cli/cache"
        // Ensure we start clean so we can prove the read created nothing.
        try? FileManager.default.removeItem(atPath: cacheDir)

        let reader = NoteStoreReader()
        let folders = try reader.fetchFolders()
        #expect(!folders.isEmpty)

        // G2 / G1: a live read must not copy the DB or create a cache dir.
        #expect(FileManager.default.fileExists(atPath: cacheDir) == false)
    }

    // MARK: - Note identifiers (write-addressable)

    @Test("note ids are x-coredata scripting ids and round-trip via fetchNote")
    func noteIDsAreScriptingIdentifiers() throws {
        guard realDBAccessible else { return }

        let reader = NoteStoreReader()
        let notes = try reader.fetchAllNotes()
        guard let first = notes.first else { return }

        // The id must be the scripting identifier the writer uses to find a note,
        // not the raw ZIDENTIFIER — otherwise "list then edit" cannot resolve it.
        #expect(first.id.hasPrefix("x-coredata://"))
        #expect(first.id.contains("/ICNote/p"))

        // Read-id == write-id: a listed id must re-fetch the same note.
        let again = try reader.fetchNote(id: first.id)
        #expect(again?.id == first.id)
        #expect(again?.name == first.name)
    }
}
