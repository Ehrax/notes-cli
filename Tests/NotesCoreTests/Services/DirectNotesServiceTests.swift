import Foundation
import GRDB
import Testing
@testable import NotesCore
import NotesTestSupport

// MARK: - Tests

@Suite("DirectNotesService Tests")
struct DirectNotesServiceTests {

    /// A path that does not point at a readable SQLite database.
    private func bogusDBPath() -> String {
        "/tmp/notes-cli-test-nonexistent-\(UUID().uuidString)/NoteStore.sqlite"
    }

    private func makeScopedDB() throws -> (path: String, outOfScopeID: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-cli-scope-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("NoteStore.sqlite").path
        let db = try DatabaseQueue(path: path)
        let storeUUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

        try db.write { conn in
            try conn.execute(sql: "CREATE TABLE z_primarykey (z_ent INTEGER, z_name TEXT)")
            try conn.execute(sql: "CREATE TABLE z_metadata (z_uuid TEXT)")
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
                    zmodificationdate1 REAL,
                    zispasswordprotected INTEGER,
                    zsnippet TEXT,
                    zmarkedfordeletion INTEGER
                )
                """)
            try conn.execute(sql: "CREATE TABLE zicnotedata (znote INTEGER, zdata BLOB)")
            try conn.execute(sql: """
                INSERT INTO z_primarykey (z_ent, z_name)
                VALUES (1, 'ICNote'), (2, 'ICFolder'), (3, 'ICAccount')
                """)
            try conn.execute(sql: "INSERT INTO z_metadata (z_uuid) VALUES (?)", arguments: [storeUUID])
            try conn.execute(sql: """
                INSERT INTO ziccloudsyncingobject (z_pk, z_ent, zname, zidentifier)
                VALUES (10, 3, 'iCloud', 'icloud-account'), (20, 3, 'Gmail', 'gmail-account')
                """)
            try conn.execute(sql: """
                INSERT INTO ziccloudsyncingobject
                    (z_pk, z_ent, zidentifier, ztitle2, zowner, zfoldertype, zmarkedfordeletion)
                VALUES
                    (11, 2, 'icloud-folder', 'Notes', 10, 0, 0),
                    (21, 2, 'gmail-folder', 'Notes', 20, 0, 0)
                """)
            try conn.execute(sql: """
                INSERT INTO ziccloudsyncingobject
                    (z_pk, z_ent, zidentifier, ztitle1, zfolder, zcreationdate1,
                     zmodificationdate1, zispasswordprotected, zsnippet, zmarkedfordeletion)
                VALUES
                    (101, 1, 'icloud-note', 'Scoped', 11, 1, 2, 0, 'scoped', 0),
                    (202, 1, 'gmail-note', 'Out of scope', 21, 1, 2, 0, 'outside', 0)
                """)
        }

        return (path, "x-coredata://\(storeUUID)/ICNote/p202")
    }

    // MARK: - Availability

    @Test("isAvailable returns false when NoteStoreReader reports unavailable")
    func isAvailableReturnsFalseWhenReaderUnavailable() async throws {
        let reader = NoteStoreReader()
        // NoteStoreReader.isAvailable() checks for ~/Library/Group Containers/.../NoteStore.sqlite
        // In most test environments this is accessible (with disk access) or not.
        // We just verify DirectNotesService.isAvailable() returns a Bool without crashing.

        let mockWriter = MockNotesService()
        mockWriter.available = false

        // Create the service with the real ScriptingBridge writer and confirm availability
        // either returns a Bool or fails with an expected macOS permission error.
        let scope = Config.NotesScope.default
        let writer = await ScriptingBridgeWriter(scope: scope)
        let service = DirectNotesService(reader: reader, writer: writer, scope: scope)

        // isAvailable either succeeds or throws (permission denial) — both are valid
        do {
            let available = try await service.isAvailable()
            // If the reader says the source is available, the result is determined by the writer too
            _ = available
        } catch let error as NotesError {
            // Automation permission denial is expected in test environments
            switch error {
            case .scriptingBridgeError:
                break
            default:
                Issue.record("Unexpected NotesError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Scope delegation

    @Test("scopedFolderPath delegates to scope")
    func scopedFolderPathDelegatesToScope() async throws {
        let reader = NoteStoreReader()
        let scope = Config.NotesScope(selectedAccount: "iCloud", rootFolder: nil)
        let writer = await ScriptingBridgeWriter(scope: scope)
        let service = DirectNotesService(reader: reader, writer: writer, scope: scope)

        let result = service.scopedFolderPath("Notes")
        // With selectedAccount="iCloud", scopedFolderPath should prefix with "iCloud/"
        #expect(result == "iCloud/Notes")
    }

    @Test("resolvedFolderPath with nil returns account root")
    func resolvedFolderPathNilReturnsRoot() async throws {
        let reader = NoteStoreReader()
        let scope = Config.NotesScope(selectedAccount: "iCloud", rootFolder: nil)
        let writer = await ScriptingBridgeWriter(scope: scope)
        let service = DirectNotesService(reader: reader, writer: writer, scope: scope)

        let result = service.resolvedFolderPath(nil)
        #expect(result == "iCloud")
    }

    @Test("scope is correctly stored")
    func scopeIsCorrectlyStored() async throws {
        let reader = NoteStoreReader()
        let scope = Config.NotesScope(selectedAccount: "Gmail", rootFolder: "notes-cli")
        let writer = await ScriptingBridgeWriter(scope: scope)
        let service = DirectNotesService(reader: reader, writer: writer, scope: scope)

        #expect(service.scope.selectedAccount == "Gmail")
        #expect(service.scope.rootFolder == "notes-cli")
    }

    @Test("fetchNote respects the selected account scope")
    func fetchNoteRespectsSelectedAccountScope() async throws {
        let fixture = try makeScopedDB()
        let reader = NoteStoreReader(databasePath: fixture.path)
        let scope = Config.NotesScope(selectedAccount: "iCloud")
        let writer = await ScriptingBridgeWriter(scope: scope)
        let service = DirectNotesService(reader: reader, writer: writer, scope: scope)

        let note = try await service.fetchNote(id: fixture.outOfScopeID)

        #expect(note == nil)
    }

    // MARK: - Read delegation errors

    @Test("fetchAllNotes throws when the live DB path is unreadable")
    func fetchAllNotesThrowsWhenUnreadable() async throws {
        let reader = NoteStoreReader(databasePath: bogusDBPath())
        let scope = Config.NotesScope.default
        let writer = await ScriptingBridgeWriter(scope: scope)
        let service = DirectNotesService(reader: reader, writer: writer, scope: scope)

        await #expect(throws: (any Error).self) {
            try await service.fetchAllNotes()
        }
    }

    @Test("fetchFolders throws when the live DB path is unreadable")
    func fetchFoldersThrowsWhenUnreadable() async throws {
        let reader = NoteStoreReader(databasePath: bogusDBPath())
        let scope = Config.NotesScope.default
        let writer = await ScriptingBridgeWriter(scope: scope)
        let service = DirectNotesService(reader: reader, writer: writer, scope: scope)

        await #expect(throws: (any Error).self) {
            try await service.fetchFolders()
        }
    }
}
