import Foundation
import Testing
@testable import NotesCore
import NotesTestSupport

@Suite("SafetyService")
struct SafetyServiceTests {

    // MARK: - Helpers

    private func makeSUT(
        config: Config = .default,
        db: MockDatabaseService = MockDatabaseService(),
        notes: MockNotesService = MockNotesService()
    ) -> (SafetyService, MockDatabaseService, MockNotesService) {
        let sut = SafetyService(
            configProvider: { config },
            db: db,
            notes: notes
        )
        return (sut, db, notes)
    }

    // MARK: - guardWrite

    @Test("Protected folder blocks writes")
    func protectedFolderBlocksWrite() async throws {
        let config = Config(protectedFolders: ["Important", "Archive"])
        let (sut, _, _) = makeSUT(config: config)

        await #expect(throws: NotesError.self) {
            try await sut.guardWrite(toFolder: "Important")
        }
    }

    @Test("Protected folder matching is case-insensitive")
    func protectedFolderCaseInsensitive() async throws {
        let config = Config(protectedFolders: ["Important"])
        let (sut, _, _) = makeSUT(config: config)

        await #expect(throws: NotesError.self) {
            try await sut.guardWrite(toFolder: "important")
        }
    }

    @Test("Protected folder blocks writes to subfolders")
    func protectedFolderBlocksSubfolder() async throws {
        let config = Config(protectedFolders: ["Work"])
        let (sut, _, _) = makeSUT(config: config)

        await #expect(throws: NotesError.self) {
            try await sut.guardWrite(toFolder: "Work/Projects")
        }
    }

    @Test("Legacy protected folder rule matches account-qualified folder paths")
    func protectedFolderMatchesAccountQualifiedPath() async throws {
        let config = Config(protectedFolders: ["Work"], notes: .init(selectedAccount: "iCloud"))
        let (sut, _, _) = makeSUT(config: config)

        await #expect(throws: NotesError.self) {
            try await sut.guardWrite(toFolder: "iCloud/Work/Projects")
        }
    }

    @Test("Non-protected folder allows writes")
    func nonProtectedFolderAllowsWrite() async throws {
        let config = Config(protectedFolders: ["Important"])
        let (sut, _, _) = makeSUT(config: config)

        // Should not throw
        try await sut.guardWrite(toFolder: "Notes")
    }

    @Test("Empty protected folders list allows all writes")
    func emptyProtectedFoldersAllowsAll() async throws {
        let (sut, _, _) = makeSUT()

        try await sut.guardWrite(toFolder: "AnyFolder")
    }

    // MARK: - guardLocked

    @Test("Locked note blocks writes when config.lockedNotes is true")
    func lockedNoteBlocksWrite() async throws {
        let config = Config(lockedNotes: true)
        let (sut, _, _) = makeSUT(config: config)

        await #expect(throws: NotesError.self) {
            try await sut.guardLocked(noteID: "note-1", isLocked: true)
        }
    }

    @Test("Locked note allows writes when config.lockedNotes is false")
    func lockedNoteAllowsWhenDisabled() async throws {
        let config = Config(lockedNotes: false)
        let (sut, _, _) = makeSUT(config: config)

        try await sut.guardLocked(noteID: "note-1", isLocked: true)
    }

    @Test("Unlocked note always allows writes")
    func unlockedNoteAllowsWrite() async throws {
        let config = Config(lockedNotes: true)
        let (sut, _, _) = makeSUT(config: config)

        try await sut.guardLocked(noteID: "note-1", isLocked: false)
    }

    // MARK: - recordAction

    @Test("Action recording stores before and after state")
    func actionRecordingStoresState() async throws {
        let db = MockDatabaseService()
        let (sut, _, _) = makeSUT(db: db)

        let before = Checkpoint(noteID: "n1", title: "Old", bodyProtobuf: Data(), bodyPlaintext: "old", folderPath: "Notes")
        let after = Checkpoint(noteID: "n1", title: "New", bodyProtobuf: Data(), bodyPlaintext: "new", folderPath: "Notes")

        try await sut.recordAction(
            type: .edit,
            noteID: "n1",
            before: before,
            after: after,
            metadata: ["source": "test"]
        )

        #expect(db.actionRecords.count == 1)
        let record = db.actionRecords[0]
        #expect(record.actionType == .edit)
        #expect(record.noteID == "n1")
        #expect(record.beforeState != nil)
        #expect(record.afterState != nil)
        #expect(record.metadata != nil)

        // Verify checkpoint can be decoded from stored JSON
        let decodedBefore = try ActionLogger.decodeCheckpoint(from: record.beforeState!)
        #expect(decodedBefore.title == "Old")
        let decodedAfter = try ActionLogger.decodeCheckpoint(from: record.afterState!)
        #expect(decodedAfter.title == "New")
    }

    // MARK: - Undo

    @Test("Undo reverses edit action by restoring before-state")
    func undoReversesEdit() async throws {
        let db = MockDatabaseService()
        let notes = MockNotesService()
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        // Set up a note
        notes.notes = [AppleNoteRaw(
            id: "n1", name: "New Title", bodyProtobuf: Data(),
            bodyPlaintext: "new",
            folderName: "Notes", folderPath: "Notes",
            creationDate: Date(), modificationDate: Date(), isLocked: false
        )]

        // Record an edit action
        let before = Checkpoint(noteID: "n1", title: "Old Title", bodyProtobuf: Data(), bodyPlaintext: "old", folderPath: "Notes")
        let after = Checkpoint(noteID: "n1", title: "New Title", bodyProtobuf: Data(), bodyPlaintext: "new", folderPath: "Notes")
        try await sut.recordAction(type: .edit, noteID: "n1", before: before, after: after, metadata: nil)

        // Undo
        let result = try await sut.undoLast()

        #expect(result != nil)
        #expect(result?.originalType == .edit)
        #expect(notes.updateNoteCalled == true)
        #expect(notes.lastUpdatedTitle == "Old Title")
        #expect(notes.lastUpdatedBody?.contains("old") == true)
    }

    @Test("Undo reverses create action — soft delete moves to Archive")
    func undoReversesCreate() async throws {
        let db = MockDatabaseService()
        let notes = MockNotesService()
        // softDelete=true (default), so undo of create moves to Archive
        notes.notes = [AppleNoteRaw(
            id: "n1", name: "New", bodyProtobuf: Data(),
            bodyPlaintext: "hi",
            folderName: "Notes",
            folderPath: "Notes", creationDate: Date(), modificationDate: Date(), isLocked: false
        )]
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        let after = Checkpoint(noteID: "n1", title: "New", bodyProtobuf: Data(), bodyPlaintext: "hi", folderPath: "Notes")
        try await sut.recordAction(type: .create, noteID: "n1", before: nil, after: after, metadata: nil)

        let result = try await sut.undoLast()

        #expect(result != nil)
        #expect(result?.originalType == .create)
        // With softDelete=true, undo moves to Archive instead of hard delete
        #expect(notes.moveNoteCalled == true)
    }

    @Test("Undo reverses create action with hard delete when softDelete=false")
    func undoReversesCreateHardDelete() async throws {
        let db = MockDatabaseService()
        let notes = MockNotesService()
        let config = Config(protectedFolders: [], lockedNotes: true, softDelete: false, undoHistory: 50)
        notes.notes = [AppleNoteRaw(
            id: "n1", name: "New", bodyProtobuf: Data(),
            bodyPlaintext: "hi",
            folderName: "Notes",
            folderPath: "Notes", creationDate: Date(), modificationDate: Date(), isLocked: false
        )]
        let (sut, _, _) = makeSUT(config: config, db: db, notes: notes)

        let after = Checkpoint(noteID: "n1", title: "New", bodyProtobuf: Data(), bodyPlaintext: "hi", folderPath: "Notes")
        try await sut.recordAction(type: .create, noteID: "n1", before: nil, after: after, metadata: nil)

        let result = try await sut.undoLast()

        #expect(result != nil)
        #expect(result?.originalType == .create)
        #expect(notes.deleteNoteCalled == true)
        #expect(notes.lastDeletedID == "n1")
    }

    @Test("Undo reverses delete action by recreating note")
    func undoReversesDelete() async throws {
        let db = MockDatabaseService()
        let notes = MockNotesService()
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        let before = Checkpoint(noteID: "n1", title: "Deleted", bodyProtobuf: Data(), bodyPlaintext: "gone", folderPath: "Notes")
        try await sut.recordAction(type: .delete, noteID: "n1", before: before, after: nil, metadata: nil)

        let result = try await sut.undoLast()

        #expect(result != nil)
        #expect(result?.originalType == .delete)
        #expect(notes.createNoteCalled == true)
        #expect(notes.lastCreatedTitle == "Deleted")
    }

    @Test("Undo reverses soft delete by restoring archived note")
    func undoReversesSoftDelete() async throws {
        let db = MockDatabaseService()
        let notes = MockNotesService()
        notes.notes = [AppleNoteRaw(
            id: "n1", name: "Archived", bodyProtobuf: Data(),
            bodyPlaintext: "gone",
            folderName: "Archive", folderPath: "Archive",
            creationDate: Date(), modificationDate: Date(), isLocked: false
        )]
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        let before = Checkpoint(noteID: "n1", title: "Archived", bodyProtobuf: Data(), bodyPlaintext: "gone", folderPath: "Notes")
        try await sut.recordAction(type: .softDelete, noteID: "n1", before: before, after: nil, metadata: nil)

        let result = try await sut.undoLast()

        #expect(result != nil)
        #expect(result?.originalType == .softDelete)
        #expect(notes.moveNoteCalled == true)
        #expect(notes.lastMovedFolder == "Notes")
        #expect(notes.createNoteCalled == false)
    }

    @Test("Soft delete inserts note into database when local row is missing")
    func softDeleteRefreshesMissingDatabaseNote() async throws {
        let db = MockDatabaseService()
        db.strictMissingNoteUpdates = true
        let notes = MockNotesService()
        let raw = AppleNoteRaw(
            id: "n1", name: "Draft", bodyProtobuf: Data(),
            bodyPlaintext: "body",
            folderName: "Notes", folderPath: "Notes",
            creationDate: Date(), modificationDate: Date(), isLocked: false
        )
        notes.notes = [raw]
        notes.fetchNoteSequence = [raw, nil]
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        try await sut.softDelete(noteID: "n1")

        let storedNote = try await db.fetchNote(id: "n1")
        #expect(storedNote != nil)
        #expect(storedNote?.folderPath == "Archive")
        #expect(db.actionRecords.count == 1)
    }

    @Test("Hard delete preserves local row when action logging fails")
    func hardDeletePreservesLocalRowWhenActionLoggingFails() async throws {
        let db = MockDatabaseService()
        db.actionRecordInsertError = NotesError.commandFailed(message: "log failed")
        let notes = MockNotesService()
        notes.notes = [AppleNoteRaw(
            id: "n1", name: "Draft", bodyProtobuf: Data(),
            bodyPlaintext: "body",
            folderName: "Notes", folderPath: "Notes",
            creationDate: Date(), modificationDate: Date(), isLocked: false
        )]
        db.notes["n1"] = Note(
            id: "n1",
            title: "Draft",
            bodyProtobuf: Data(),
            bodyPlaintext: "body",
            folderPath: "Notes",
            syncedAt: Date()
        )
        let config = Config(protectedFolders: [], lockedNotes: true, softDelete: false, undoHistory: 50)
        let (sut, _, _) = makeSUT(config: config, db: db, notes: notes)

        await #expect(throws: NotesError.self) {
            try await sut.softDelete(noteID: "n1")
        }

        #expect(notes.deleteNoteCalled == true)
        let storedNote = try await db.fetchNote(id: "n1")
        #expect(storedNote != nil)
        #expect(db.actionRecords.isEmpty)
    }

    @Test("Undo create with soft delete updates database to Archive when refetch misses")
    func undoCreateSoftDeleteRefreshesArchiveFallback() async throws {
        let db = MockDatabaseService()
        let storedNote = Note(
            id: "n1",
            title: "New",
            bodyProtobuf: Data(),
            bodyPlaintext: "hi",
            folderPath: "Notes",
            syncedAt: Date()
        )
        db.notes["n1"] = storedNote

        let notes = MockNotesService()
        let currentRaw = AppleNoteRaw(
            id: "n1", name: "New", bodyProtobuf: Data(),
            bodyPlaintext: "hi",
            folderName: "Notes",
            folderPath: "Notes", creationDate: Date(), modificationDate: Date(), isLocked: false
        )
        notes.notes = [currentRaw]
        notes.fetchNoteSequence = [currentRaw, nil]
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        let after = Checkpoint(noteID: "n1", title: "New", bodyProtobuf: Data(), bodyPlaintext: "hi", folderPath: "Notes")
        try await sut.recordAction(type: .create, noteID: "n1", before: nil, after: after, metadata: nil)

        _ = try await sut.undoLast()

        let refreshedNote = try await db.fetchNote(id: "n1")
        #expect(refreshedNote?.folderPath == "Archive")
    }

    @Test("Undo reverses move action by moving note back")
    func undoReversesMove() async throws {
        let db = MockDatabaseService()
        let notes = MockNotesService()
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        let before = Checkpoint(noteID: "n1", title: "Note", bodyProtobuf: Data(), bodyPlaintext: "hi", folderPath: "OldFolder")
        let after = Checkpoint(noteID: "n1", title: "Note", bodyProtobuf: Data(), bodyPlaintext: "hi", folderPath: "NewFolder")
        try await sut.recordAction(type: .move, noteID: "n1", before: before, after: after, metadata: nil)

        let result = try await sut.undoLast()

        #expect(result != nil)
        #expect(result?.originalType == .move)
        #expect(notes.moveNoteCalled == true)
        #expect(notes.lastMovedFolder == "OldFolder")
    }

    @Test("Undo returns nil when no actions exist")
    func undoReturnsNilWhenEmpty() async throws {
        let (sut, _, _) = makeSUT()
        let result = try await sut.undoLast()
        #expect(result == nil)
    }

    // MARK: - softDelete

    @Test("Soft delete records action and moves note to Archive")
    func softDeleteMovesToArchive() async throws {
        let db = MockDatabaseService()
        let notes = MockNotesService()
        notes.notes = [AppleNoteRaw(
            id: "n1", name: "My Note", bodyProtobuf: Data(),
            bodyPlaintext: "content",
            folderName: "Notes", folderPath: "Notes",
            creationDate: Date(), modificationDate: Date(), isLocked: false
        )]
        let (sut, _, _) = makeSUT(db: db, notes: notes)

        try await sut.softDelete(noteID: "n1")

        #expect(db.actionRecords.count == 1)
        #expect(db.actionRecords[0].actionType == .softDelete)
        #expect(notes.moveNoteCalled == true)
        #expect(notes.lastMovedFolder == "Archive")
    }
}
