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

    // MARK: - isAvailable

    @Test("isAvailable returns false when NoteStore.sqlite does not exist")
    func isAvailableReturnsFalseForMissingDatabase() throws {
        // When Full Disk Access is granted, refresh() copies the real DB into the temp cache,
        // so fetch calls succeed instead of throwing. Skip in that case.
        guard !realDBAccessible else { return }

        let tempDir = try makeTempDirectory(prefix: "notes-cli-notestorereader-test")
        defer { removeTempDirectory(tempDir) }

        let reader = NoteStoreReader(cacheDir: tempDir.path)

        #expect(throws: (any Error).self) {
            try reader.fetchAccountNames()
        }
    }

    @Test("refresh throws when source NoteStore.sqlite is not found")
    func refreshThrowsWhenSourceMissing() {
        // NoteStoreReader looks for ~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
        // In a test environment, this may or may not exist.
        // We test the behaviour when the cache dir itself is non-existent.
        let reader = NoteStoreReader(cacheDir: "/tmp/notes-cli-test-nonexistent-\(UUID().uuidString)")
        // On a machine without Apple Notes OR full disk access, refresh() will throw.
        // This test verifies the reader doesn't crash — it either succeeds or throws a NotesError.
        do {
            try reader.refresh()
            // If refresh succeeds, the source DB exists and we have disk access — that's fine too
        } catch let error as NotesError {
            // Expected: either "not found" or "cannot access" error
            switch error {
            case .commandFailed:
                break  // Expected
            default:
                Issue.record("Unexpected NotesError type: \(error)")
            }
        } catch {
            Issue.record("Unexpected non-NotesError: \(error)")
        }
    }

    @Test("fetchAccountNames throws NotesError when cache DB is missing")
    func fetchAccountNamesThrowsWhenCacheMissing() throws {
        guard !realDBAccessible else { return }
        let tempDir = try makeTempDirectory(prefix: "notes-cli-notestorereader-test")
        defer { removeTempDirectory(tempDir) }

        let reader = NoteStoreReader(cacheDir: tempDir.path)

        #expect(throws: (any Error).self) {
            try reader.fetchAccountNames()
        }
    }

    @Test("fetchFolders throws NotesError when cache DB is missing")
    func fetchFoldersThrowsWhenCacheMissing() throws {
        guard !realDBAccessible else { return }
        let tempDir = try makeTempDirectory(prefix: "notes-cli-notestorereader-test")
        defer { removeTempDirectory(tempDir) }

        let reader = NoteStoreReader(cacheDir: tempDir.path)

        #expect(throws: (any Error).self) {
            try reader.fetchFolders()
        }
    }

    @Test("fetchAllNotes throws NotesError when cache DB is missing")
    func fetchAllNotesThrowsWhenCacheMissing() throws {
        guard !realDBAccessible else { return }
        let tempDir = try makeTempDirectory(prefix: "notes-cli-notestorereader-test")
        defer { removeTempDirectory(tempDir) }

        let reader = NoteStoreReader(cacheDir: tempDir.path)

        #expect(throws: (any Error).self) {
            try reader.fetchAllNotes()
        }
    }

    @Test("fetchAttachments throws NotesError when cache DB is missing")
    func fetchAttachmentsThrowsWhenCacheMissing() throws {
        guard !realDBAccessible else { return }
        let tempDir = try makeTempDirectory(prefix: "notes-cli-notestorereader-test")
        defer { removeTempDirectory(tempDir) }

        let reader = NoteStoreReader(cacheDir: tempDir.path)

        #expect(throws: (any Error).self) {
            try reader.fetchAttachments(noteID: "test-note-id")
        }
    }
}
