import Foundation
import Testing

@testable import NotesCore
import NotesTestSupport

@Suite("SyncService Tests")
struct SyncServiceTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSyncService(
        notesService: MockNotesService = MockNotesService(),
        dbService: MockDatabaseService = MockDatabaseService()
    ) -> (SyncService, MockNotesService, MockDatabaseService) {
        let sync = SyncService(db: dbService, notes: notesService)
        return (sync, notesService, dbService)
    }

    private func makeAppleNote(
        id: String = "note-1",
        name: String = "Test Note",
        bodyProtobuf: Data = Data(),
        bodyPlaintext: String = "Hello",
        folderName: String = "Notes",
        folderPath: String = "Notes",
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        isLocked: Bool = false
    ) -> AppleNoteRaw {
        let resolvedCreationDate = creationDate ?? referenceDate
        let resolvedModificationDate = modificationDate ?? resolvedCreationDate
        return AppleNoteRaw(
            id: id,
            name: name,
            bodyProtobuf: bodyProtobuf,
            bodyPlaintext: bodyPlaintext,
            folderName: folderName,
            folderPath: folderPath,
            creationDate: resolvedCreationDate,
            modificationDate: resolvedModificationDate,
            isLocked: isLocked
        )
    }

    private func makeNote(
        id: String = "note-1",
        title: String = "Test Note",
        bodyProtobuf: Data = Data(),
        bodyPlaintext: String = "Hello",
        folderPath: String = "Notes",
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        syncedAt: Date = Date()
    ) -> Note {
        let resolvedCreationDate = creationDate ?? referenceDate
        let resolvedModificationDate = modificationDate ?? resolvedCreationDate
        return Note(
            id: id,
            title: title,
            bodyProtobuf: bodyProtobuf,
            bodyPlaintext: bodyPlaintext,
            folderPath: folderPath,
            creationDate: resolvedCreationDate,
            modificationDate: resolvedModificationDate,
            syncedAt: syncedAt
        )
    }

    // MARK: - Full Sync: Add New Notes

    @Test("Full sync adds new notes to empty DB")
    func fullSyncAddsNewNotes() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        notesService.notes = [
            makeAppleNote(id: "n1", name: "Note One", bodyPlaintext: "Body 1"),
            makeAppleNote(id: "n2", name: "Note Two", bodyPlaintext: "Body 2"),
        ]

        let result = try await sync.fullSync()

        #expect(result.added == 2)
        #expect(result.updated == 0)
        #expect(result.deleted == 0)
        #expect(result.unchanged == 0)
        #expect(result.errors.isEmpty)
        #expect(notesService.fetchAllNotesCalled)
        #expect(notesService.fetchAllNoteMetadataCalled == false)
        #expect(notesService.fetchedNoteIDs.isEmpty)

        let storedNotes = try await dbService.fetchAllNotes()
        #expect(storedNotes.count == 2)
    }

    // MARK: - Full Sync: Detect Modified Notes

    @Test("Full sync detects modified notes by checksum difference")
    func fullSyncDetectsModifiedNotes() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        // Pre-populate DB with a note
        let existingNote = makeNote(
            id: "n1",
            title: "Old Title",
            bodyPlaintext: "Old body"
        )
        try await dbService.insertNote(existingNote)

        // Apple Notes has the same note but with different body
        notesService.notes = [
            makeAppleNote(id: "n1", name: "New Title", bodyPlaintext: "New body")
        ]

        let result = try await sync.fullSync()

        #expect(result.added == 0)
        #expect(result.updated == 1)
        #expect(result.deleted == 0)
        #expect(result.unchanged == 0)
        #expect(result.errors.isEmpty)

        let updatedNote = try await dbService.fetchNote(id: "n1")
        #expect(updatedNote?.title == "New Title")
    }

    @Test("Full sync detects non-body note changes")
    func fullSyncDetectsNonBodyChanges() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        try await dbService.insertNote(makeNote(id: "n1", title: "Original", folderPath: "Notes"))

        notesService.notes = [
            makeAppleNote(id: "n1", name: "Renamed", folderPath: "Work")
        ]

        let result = try await sync.fullSync()

        #expect(result.updated == 1)
        let updatedNote = try await dbService.fetchNote(id: "n1")
        #expect(updatedNote?.title == "Renamed")
        #expect(updatedNote?.folderPath == "Work")
    }

    // MARK: - Full Sync: Detect Deleted Notes

    @Test("Full sync detects deleted notes (in DB but not in Apple Notes)")
    func fullSyncDetectsDeletedNotes() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        // Pre-populate DB with notes
        try await dbService.insertNote(makeNote(id: "n1"))
        try await dbService.insertNote(makeNote(id: "n2", title: "Note Two", bodyPlaintext: "Two"))

        // Apple Notes only has one of them
        notesService.notes = [
            makeAppleNote(id: "n1")
        ]

        let result = try await sync.fullSync()

        #expect(result.deleted == 1)
        #expect(result.unchanged == 1)

        let remaining = try await dbService.fetchAllNotes()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == "n1")
    }

    // MARK: - Full Sync: Unchanged Notes

    @Test("Full sync handles unchanged notes with same checksum")
    func fullSyncHandlesUnchangedNotes() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        let bodyData = Data("Same body".utf8)
        try await dbService.insertNote(makeNote(id: "n1", bodyProtobuf: bodyData))

        notesService.notes = [
            makeAppleNote(id: "n1", bodyProtobuf: bodyData)
        ]

        let result = try await sync.fullSync()

        #expect(result.added == 0)
        #expect(result.updated == 0)
        #expect(result.deleted == 0)
        #expect(result.unchanged == 1)
        #expect(result.errors.isEmpty)
    }

    // MARK: - Incremental Sync

    @Test("Incremental sync only processes notes modified after last sync")
    func incrementalSyncOnlyProcessesRecentChanges() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        let oldDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let recentDate = Date(timeIntervalSinceNow: -60) // 1 minute ago

        // Set last sync to 30 min ago
        let lastSync = Date(timeIntervalSinceNow: -1800)
        let formatter = ISO8601DateFormatter()
        try await dbService.setSyncState(
            key: SyncService.lastSyncKey,
            value: formatter.string(from: lastSync)
        )

        // DB has two notes
        try await dbService.insertNote(
            makeNote(
                id: "n1",
                bodyPlaintext: "Old",
                creationDate: oldDate,
                modificationDate: oldDate
            )
        )
        try await dbService.insertNote(
            makeNote(
                id: "n2",
                bodyPlaintext: "Unchanged",
                creationDate: oldDate,
                modificationDate: oldDate
            )
        )

        // Apple Notes: n1 modified recently with new body, n2 not modified
        notesService.notes = [
            makeAppleNote(id: "n1", bodyPlaintext: "Updated", creationDate: oldDate, modificationDate: recentDate),
            makeAppleNote(id: "n2", bodyPlaintext: "Unchanged", creationDate: oldDate, modificationDate: oldDate),
        ]

        let result = try await sync.incrementalSync()

        #expect(result.updated == 1)
        #expect(result.unchanged == 1)
        #expect(result.errors.isEmpty)
        #expect(notesService.fetchAllNoteMetadataCalled)
        #expect(notesService.fetchedNoteIDs == ["n1"])
    }

    @Test("Incremental sync behaves like full sync when no last sync timestamp exists")
    func incrementalSyncWithoutTimestampHydratesAllNotes() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        notesService.notes = [
            makeAppleNote(id: "n1", name: "Note One", bodyPlaintext: "One"),
            makeAppleNote(id: "n2", name: "Note Two", bodyPlaintext: "Two"),
        ]

        let result = try await sync.incrementalSync()

        #expect(result.added == 2)
        #expect(result.errors.isEmpty)
        #expect(Set(notesService.fetchedNoteIDs) == Set(["n1", "n2"]))

        let storedNotes = try await dbService.fetchAllNotes()
        #expect(storedNotes.count == 2)
    }

    @Test("Incremental sync hydrates notes when metadata changes")
    func incrementalSyncHydratesMetadataChanges() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        let oldDate = Date(timeIntervalSinceNow: -3600)
        let recentDate = Date(timeIntervalSinceNow: -60)
        let lastSync = Date(timeIntervalSinceNow: -1800)
        let formatter = ISO8601DateFormatter()

        try await dbService.setSyncState(key: SyncService.lastSyncKey, value: formatter.string(from: lastSync))
        try await dbService.insertNote(
            makeNote(
                id: "n1",
                title: "Original",
                bodyPlaintext: "Hello",
                folderPath: "Notes",
                syncedAt: oldDate
            )
        )

        notesService.notes = [
            makeAppleNote(
                id: "n1",
                name: "Renamed",
                folderPath: "Work",
                modificationDate: recentDate
            )
        ]

        let result = try await sync.incrementalSync()

        #expect(result.updated == 1)
        #expect(notesService.fetchedNoteIDs == ["n1"])

        let updatedNote = try await dbService.fetchNote(id: "n1")
        #expect(updatedNote?.title == "Renamed")
        #expect(updatedNote?.folderPath == "Work")
    }

    @Test("Incremental sync ignores subsecond timestamp drift for unchanged notes")
    func incrementalSyncIgnoresSubsecondTimestampDrift() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        let baseTimestamp = Date(timeIntervalSince1970: 1_700_000_000.1)
        let driftedTimestamp = Date(timeIntervalSince1970: 1_700_000_000.9)
        let lastSync = Date(timeIntervalSince1970: 1_700_000_100)
        let formatter = ISO8601DateFormatter()

        try await dbService.setSyncState(key: SyncService.lastSyncKey, value: formatter.string(from: lastSync))
        let stableData = Data("Stable".utf8)
        try await dbService.insertNote(
            makeNote(
                id: "n1",
                bodyProtobuf: stableData,
                bodyPlaintext: "Stable",
                creationDate: baseTimestamp,
                modificationDate: baseTimestamp
            )
        )

        notesService.notes = [
            makeAppleNote(
                id: "n1",
                bodyProtobuf: stableData,
                bodyPlaintext: "Stable",
                creationDate: driftedTimestamp,
                modificationDate: driftedTimestamp
            )
        ]

        let result = try await sync.incrementalSync()

        #expect(result.unchanged == 1)
        #expect(result.updated == 0)
        #expect(notesService.fetchedNoteIDs.isEmpty)
    }

    @Test("Incremental sync records hydration errors when full note fetch is missing")
    func incrementalSyncRecordsHydrationErrors() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        let lastSync = Date(timeIntervalSinceNow: -1800)
        let recentDate = Date(timeIntervalSinceNow: -60)
        let formatter = ISO8601DateFormatter()

        try await dbService.setSyncState(key: SyncService.lastSyncKey, value: formatter.string(from: lastSync))
        try await dbService.insertNote(makeNote(id: "n1", bodyPlaintext: "Old"))

        notesService.noteMetadata = [
            AppleNoteMetadata(
                id: "n1",
                name: "Test Note",
                folderName: "Notes",
                folderPath: "Notes",
                creationDate: Date(),
                modificationDate: recentDate,
                isLocked: false
            )
        ]
        notesService.fetchNoteSequence = [nil]

        let result = try await sync.incrementalSync()

        #expect(result.updated == 0)
        #expect(result.errors.count == 1)
        let timestamp = try await dbService.getSyncState(key: SyncService.lastSyncKey)
        #expect(timestamp == formatter.string(from: lastSync))
    }

    // MARK: - Sync Records Timestamp

    @Test("Sync records timestamp in syncState")
    func syncRecordsTimestamp() async throws {
        let (sync, _, dbService) = makeSyncService()

        _ = try await sync.fullSync()

        let timestamp = try await dbService.getSyncState(key: SyncService.lastSyncKey)
        #expect(timestamp != nil)

        // Verify it parses as a valid date
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: timestamp!)
        #expect(date != nil)
    }

    @Test("Sync skips timestamp update after partial failures")
    func syncSkipsTimestampUpdateAfterPartialFailures() async throws {
        let (sync, notesService, dbService) = makeSyncService()
        dbService.noteInsertFailures = ["n2"]

        notesService.notes = [
            makeAppleNote(id: "n1", bodyPlaintext: "One"),
            makeAppleNote(id: "n2", bodyPlaintext: "Two")
        ]

        let result = try await sync.fullSync()

        #expect(result.added == 1)
        #expect(result.errors.count == 1)
        let timestamp = try await dbService.getSyncState(key: SyncService.lastSyncKey)
        #expect(timestamp == nil)
    }

    @Test("Folder sync updates renamed folder by stable ID")
    func folderSyncUpdatesRenamedFolderByID() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        try await dbService.insertFolder(Folder(id: "f1", name: "Work", path: "Work"))
        notesService.folders = [AppleFolderRaw(id: "f1", name: "Projects", path: "Projects", parentPath: nil)]

        _ = try await sync.fullSync()

        let oldFolder = try await dbService.fetchFolder(path: "Work")
        let renamedFolder = try await dbService.fetchFolder(path: "Projects")
        #expect(oldFolder == nil)
        #expect(renamedFolder?.id == "f1")
        #expect(renamedFolder?.name == "Projects")
    }

    @Test("Full sync keeps duplicate folder names distinct across accounts")
    func fullSyncKeepsDuplicateFolderNamesDistinctAcrossAccounts() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        notesService.notes = [
            makeAppleNote(id: "n1", folderName: "Notes", folderPath: "iCloud/Notes"),
            makeAppleNote(id: "n2", folderName: "Notes", folderPath: "Gmail/Notes")
        ]
        notesService.folders = [
            AppleFolderRaw(id: "f1", name: "Notes", path: "iCloud/Notes", parentPath: nil),
            AppleFolderRaw(id: "f2", name: "Notes", path: "Gmail/Notes", parentPath: nil),
        ]

        let result = try await sync.fullSync()

        #expect(result.added == 2)
        let syncedNotes = try await dbService.fetchAllNotes()
        #expect(Set(syncedNotes.map(\.folderPath)) == Set(["iCloud/Notes", "Gmail/Notes"]))

        let syncedFolders = try await dbService.fetchAllFolders()
        #expect(syncedFolders.count == 2)
        #expect(Set(syncedFolders.map(\.path)) == Set(["iCloud/Notes", "Gmail/Notes"]))
    }

    // MARK: - Empty Apple Notes Deletes All DB Notes

    @Test("Empty Apple Notes results in all DB notes being deleted")
    func emptyAppleNotesDeletesAll() async throws {
        let (sync, notesService, dbService) = makeSyncService()

        try await dbService.insertNote(makeNote(id: "n1"))
        try await dbService.insertNote(makeNote(id: "n2", title: "Two", bodyPlaintext: "Two"))
        try await dbService.insertNote(makeNote(id: "n3", title: "Three", bodyPlaintext: "Three"))

        notesService.notes = []

        let result = try await sync.fullSync()

        #expect(result.added == 0)
        #expect(result.updated == 0)
        #expect(result.deleted == 3)
        #expect(result.unchanged == 0)

        let remaining = try await dbService.fetchAllNotes()
        #expect(remaining.isEmpty)
    }
}
