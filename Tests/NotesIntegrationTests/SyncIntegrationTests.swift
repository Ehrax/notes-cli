import Foundation
import Testing
import NotesCore
import NotesTestSupport

@Suite("Sync Integration Tests")
struct SyncIntegrationTests {

    // MARK: - Full sync populates DB and FTS search works

    @Test("Full sync populates DB and FTS search returns results")
    func fullSyncPopulatesDBAndFTSWorks() async throws {
        let db = try makeRealDatabase()
        let notes = MockNotesService()
        notes.notes = [
            makeSampleAppleNote(id: "n1", name: "Swift Programming Guide",
                bodyPlaintext: "Learn Swift concurrency"),
            makeSampleAppleNote(id: "n2", name: "Cooking Recipes",
                bodyPlaintext: "Pasta carbonara recipe"),
        ]
        let sync = SyncService(db: db, notes: notes)

        let result = try await sync.fullSync()

        #expect(result.added == 2)
        #expect(result.errors.isEmpty)

        // Verify FTS5 search works end-to-end
        let searchResults = try await db.searchNotes(query: "swift")
        #expect(searchResults.count == 1)
        #expect(searchResults.first?.id == "n1")

        let bodySearch = try await db.searchNotes(query: "carbonara")
        #expect(bodySearch.count == 1)
        #expect(bodySearch.first?.id == "n2")
    }

    // MARK: - Full sync preserves folder structure

    @Test("Full sync preserves folder structure in DB")
    func fullSyncPreservesFolderStructure() async throws {
        let db = try makeRealDatabase()
        let notes = MockNotesService()
        notes.notes = [
            makeSampleAppleNote(id: "n1", name: "Work Note 1", bodyPlaintext: "Work stuff", folder: "Work"),
            makeSampleAppleNote(id: "n2", name: "Work Note 2", bodyPlaintext: "More work", folder: "Work"),
            makeSampleAppleNote(id: "n3", name: "Personal Note", bodyPlaintext: "Personal stuff", folder: "Personal"),
        ]
        notes.folders = [
            AppleFolderRaw(id: "f1", name: "Work", path: "Work", parentPath: nil),
            AppleFolderRaw(id: "f2", name: "Personal", path: "Personal", parentPath: nil),
        ]
        let sync = SyncService(db: db, notes: notes)

        let result = try await sync.fullSync()
        #expect(result.added == 3)

        let workNotes = try await db.fetchNotes(inFolder: "Work")
        #expect(workNotes.count == 2)

        let personalNotes = try await db.fetchNotes(inFolder: "Personal")
        #expect(personalNotes.count == 1)

        let allFolders = try await db.fetchAllFolders()
        #expect(allFolders.count >= 2)
    }

    // MARK: - Incremental sync after full sync

    @Test("Incremental sync detects add, modify, and delete after full sync")
    func incrementalSyncAfterFullSync() async throws {
        let db = try makeRealDatabase()
        let notes = MockNotesService()
        notes.notes = [
            makeSampleAppleNote(id: "n1", name: "Note One", bodyPlaintext: "Original"),
            makeSampleAppleNote(id: "n2", name: "Note Two", bodyPlaintext: "Will be deleted"),
        ]
        let sync = SyncService(db: db, notes: notes)

        // Full sync first
        _ = try await sync.fullSync()
        notes.fetchedNoteIDs = []

        // Mutate: modify n1, delete n2, add n3
        let recentDate = Date(timeIntervalSinceNow: 60)
        notes.notes = [
            makeSampleAppleNote(
                id: "n1", name: "Note One Updated", bodyPlaintext: "Modified body",
                modificationDate: recentDate
            ),
            makeSampleAppleNote(
                id: "n3", name: "Note Three", bodyPlaintext: "Brand new",
                modificationDate: recentDate
            ),
        ]

        let result = try await sync.incrementalSync()

        #expect(result.added == 1)
        #expect(result.updated == 1)
        #expect(result.deleted == 1)
        #expect(result.errors.isEmpty)

        // Verify DB state
        let allNotes = try await db.fetchAllNotes()
        #expect(allNotes.count == 2)
        let ids = Set(allNotes.map(\.id))
        #expect(ids.contains("n1"))
        #expect(ids.contains("n3"))
        #expect(!ids.contains("n2"))
        #expect(Set(notes.fetchedNoteIDs) == Set(["n1", "n3"]))
    }

    @Test("Incremental sync without existing timestamp behaves like initial full sync")
    func incrementalSyncWithoutTimestampPopulatesDBAndFTSWorks() async throws {
        let db = try makeRealDatabase()
        let notes = MockNotesService()
        notes.notes = [
            makeSampleAppleNote(id: "n1", name: "Swift Programming Guide",
                bodyPlaintext: "Learn Swift concurrency"),
            makeSampleAppleNote(id: "n2", name: "Cooking Recipes",
                bodyPlaintext: "Pasta carbonara recipe"),
        ]
        let sync = SyncService(db: db, notes: notes)

        let result = try await sync.incrementalSync()

        #expect(result.added == 2)
        #expect(result.errors.isEmpty)
        #expect(Set(notes.fetchedNoteIDs) == Set(["n1", "n2"]))

        let searchResults = try await db.searchNotes(query: "swift")
        #expect(searchResults.count == 1)
        let bodySearch = try await db.searchNotes(query: "carbonara")
        #expect(bodySearch.count == 1)
    }

    @Test("Incremental sync skips hydrating unchanged notes")
    func incrementalSyncSkipsHydratingUnchangedNotes() async throws {
        let db = try makeRealDatabase()
        let notes = MockNotesService()
        let oldDate = Date(timeIntervalSinceNow: -3600)
        let lastSync = Date(timeIntervalSinceNow: -1800)
        let formatter = ISO8601DateFormatter()

        notes.notes = [
            makeSampleAppleNote(id: "n1", name: "Stable", bodyPlaintext: "Body", modificationDate: oldDate)
        ]
        let sync = SyncService(db: db, notes: notes)

        _ = try await sync.fullSync()
        notes.fetchedNoteIDs = []
        try await db.setSyncState(key: SyncService.lastSyncKey, value: formatter.string(from: lastSync))

        let result = try await sync.incrementalSync()

        #expect(result.unchanged == 1)
        #expect(notes.fetchedNoteIDs.isEmpty)
    }

    // MARK: - Sync timestamp persists through real DB

    @Test("Sync timestamp persists in real DB as valid ISO8601")
    func syncTimestampPersists() async throws {
        let db = try makeRealDatabase()
        let notes = MockNotesService()
        let sync = SyncService(db: db, notes: notes)

        _ = try await sync.fullSync()

        let timestamp = try await db.getSyncState(key: SyncService.lastSyncKey)
        #expect(timestamp != nil)

        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: timestamp!)
        #expect(date != nil)

        // Verify the timestamp is recent (within last minute)
        let interval = Date().timeIntervalSince(date!)
        #expect(interval < 60)
    }

    // MARK: - Large batch sync

    @Test("Large batch sync inserts all notes correctly")
    func largeBatchSync() async throws {
        let db = try makeRealDatabase()
        let notes = makePopulatedMockNotes(count: 50)
        let sync = SyncService(db: db, notes: notes)

        let result = try await sync.fullSync()

        #expect(result.added == 50)
        #expect(result.errors.isEmpty)

        let allNotes = try await db.fetchAllNotes()
        #expect(allNotes.count == 50)
    }
}
