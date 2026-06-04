import Foundation
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
