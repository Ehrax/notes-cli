import Foundation
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
