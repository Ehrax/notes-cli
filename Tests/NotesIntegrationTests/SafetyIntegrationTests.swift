import Foundation
import Testing
import NotesCore
import NotesTestSupport

@Suite("Safety Integration Tests")
struct SafetyIntegrationTests {

    private func makeSUT(
        config: Config = .default,
        db: DatabaseService? = nil,
        notes: MockNotesService = MockNotesService()
    ) throws -> (SafetyService, DatabaseService, MockNotesService) {
        let realDB = try db ?? makeRealDatabase()
        let sut = SafetyService(
            configProvider: { config },
            db: realDB,
            notes: notes
        )
        return (sut, realDB, notes)
    }

    /// Inserts a note into the real DB so FK constraints on actionLog are satisfied.
    private func seedNote(db: DatabaseService, id: String = "n1") async throws {
        try await db.insertNote(Note(
            id: id, title: "Seed", bodyProtobuf: Data(),
            bodyPlaintext: "seed", folderPath: "Notes"
        ))
    }

    // MARK: - Record action persists and is retrievable

    @Test("Record action persists in real DB and is retrievable via history")
    func recordActionPersistsAndRetrievable() async throws {
        let (sut, db, _) = try makeSUT()
        try await seedNote(db: db)

        let before = Checkpoint(noteID: "n1", title: "Old", bodyProtobuf: Data(), bodyPlaintext: "old", folderPath: "Notes")
        let after = Checkpoint(noteID: "n1", title: "New", bodyProtobuf: Data(), bodyPlaintext: "new", folderPath: "Notes")

        try await sut.recordAction(type: .edit, noteID: "n1", before: before, after: after, metadata: ["source": "test"])

        let history = try await sut.history(noteID: "n1", limit: 10)
        #expect(history.count == 1)
        #expect(history[0].type == .edit)
        #expect(history[0].noteID == "n1")

        // Verify the raw action record has persisted state
        let records = try await db.fetchActionRecords(forNoteID: "n1")
        #expect(records.count == 1)
        #expect(records[0].beforeState != nil)
        #expect(records[0].afterState != nil)
    }

    // MARK: - Record action and undo full cycle

    @Test("Record action and undo full cycle through real DB")
    func recordActionAndUndoFullCycle() async throws {
        let notes = MockNotesService()
        notes.notes = [
            AppleNoteRaw(
                id: "n1", name: "New Title", bodyProtobuf: Data(),
                bodyPlaintext: "new",
                folderName: "Notes", folderPath: "Notes",
                creationDate: Date(), modificationDate: Date(), isLocked: false
            ),
        ]
        let (sut, db, _) = try makeSUT(notes: notes)
        try await seedNote(db: db)

        let before = Checkpoint(noteID: "n1", title: "Old Title", bodyProtobuf: Data(), bodyPlaintext: "old", folderPath: "Notes")
        let after = Checkpoint(noteID: "n1", title: "New Title", bodyProtobuf: Data(), bodyPlaintext: "new", folderPath: "Notes")

        try await sut.recordAction(type: .edit, noteID: "n1", before: before, after: after, metadata: nil)

        // Undo
        let result = try await sut.undoLast()
        #expect(result != nil)
        #expect(result?.originalType == .edit)
        #expect(notes.updateNoteCalled)
        #expect(notes.lastUpdatedTitle == "Old Title")

        // Verify action is marked undone in DB
        let record = try await db.fetchLatestActionRecord()
        #expect(record?.undone == true)
    }

    // MARK: - Soft delete records checkpoint and is undoable

    @Test("Soft delete records checkpoint and is undoable")
    func softDeleteAndUndo() async throws {
        let notes = MockNotesService()
        notes.notes = [
            AppleNoteRaw(
                id: "n1", name: "My Note", bodyProtobuf: Data(),
                bodyPlaintext: "content",
                folderName: "Notes", folderPath: "Notes",
                creationDate: Date(), modificationDate: Date(), isLocked: false
            ),
        ]
        let (sut, db, _) = try makeSUT(notes: notes)
        try await seedNote(db: db)

        // Soft delete
        try await sut.softDelete(noteID: "n1")

        #expect(notes.moveNoteCalled)
        #expect(notes.lastMovedFolder == "Archive")

        // Verify action was recorded
        let history = try await sut.history(noteID: nil, limit: 10)
        #expect(history.count == 1)
        #expect(history[0].type == .softDelete)

        // Reset mock state for undo verification
        notes.moveNoteCalled = false
        notes.createNoteCalled = false

        // Undo the soft delete (should restore the archived original)
        let undoResult = try await sut.undoLast()
        #expect(undoResult != nil)
        #expect(undoResult?.originalType == .softDelete)
        #expect(notes.moveNoteCalled)
        #expect(notes.lastMovedFolder == "Notes")
        #expect(notes.createNoteCalled == false)
    }

    @Test("Hard delete records history after note row removal")
    func hardDeleteRecordsHistory() async throws {
        let config = Config(protectedFolders: [], lockedNotes: true, softDelete: false, undoHistory: 50)
        let notes = MockNotesService()
        notes.notes = [
            AppleNoteRaw(
                id: "n1", name: "My Note", bodyProtobuf: Data(),
                bodyPlaintext: "content",
                folderName: "Notes", folderPath: "Notes",
                creationDate: Date(), modificationDate: Date(), isLocked: false
            ),
        ]
        let (sut, _, _) = try makeSUT(config: config, notes: notes)

        try await sut.softDelete(noteID: "n1")

        let history = try await sut.history(noteID: nil, limit: 10)
        #expect(history.count == 1)
        #expect(history[0].type == .delete)
    }

    // MARK: - Multiple actions produce ordered history

    @Test("Multiple actions produce newest-first ordered history")
    func multipleActionsOrderedHistory() async throws {
        let (sut, db, _) = try makeSUT()
        try await seedNote(db: db)

        let cp1 = Checkpoint(noteID: "n1", title: "T1", bodyProtobuf: Data(), bodyPlaintext: "1", folderPath: "Notes")
        let cp2 = Checkpoint(noteID: "n1", title: "T2", bodyProtobuf: Data(), bodyPlaintext: "2", folderPath: "Notes")
        let cp3 = Checkpoint(noteID: "n1", title: "T3", bodyProtobuf: Data(), bodyPlaintext: "3", folderPath: "Notes")

        try await sut.recordAction(type: .create, noteID: "n1", before: nil, after: cp1, metadata: nil)
        try await sut.recordAction(type: .edit, noteID: "n1", before: cp1, after: cp2, metadata: nil)
        try await sut.recordAction(type: .edit, noteID: "n1", before: cp2, after: cp3, metadata: nil)

        let history = try await sut.history(noteID: nil, limit: 10)
        #expect(history.count == 3)

        // Newest first
        #expect(history[0].type == .edit)
        #expect(history[2].type == .create)

        // Timestamps should be in descending order
        for i in 0..<(history.count - 1) {
            #expect(history[i].timestamp >= history[i + 1].timestamp)
        }
    }

    // MARK: - Guard write + action + undo cycle

    @Test("Guard write blocks protected folder, allows unprotected, and undo works")
    func guardWriteAndUndoCycle() async throws {
        let config = Config(protectedFolders: ["Important"], lockedNotes: true, softDelete: true, undoHistory: 50)
        let notes = MockNotesService()
        notes.notes = [
            AppleNoteRaw(
                id: "n1", name: "Test", bodyProtobuf: Data(),
                bodyPlaintext: "hi",
                folderName: "Notes", folderPath: "Notes",
                creationDate: Date(), modificationDate: Date(), isLocked: false
            ),
        ]
        let (sut, db, _) = try makeSUT(config: config, notes: notes)
        try await seedNote(db: db)

        // Protected folder should block
        await #expect(throws: NotesError.self) {
            try await sut.guardWrite(toFolder: "Important")
        }

        // Allowed folder should not block
        try await sut.guardWrite(toFolder: "Notes")

        // Record an action on allowed folder
        let before = Checkpoint(noteID: "n1", title: "Test", bodyProtobuf: Data(), bodyPlaintext: "hi", folderPath: "Notes")
        let after = Checkpoint(noteID: "n1", title: "Updated", bodyProtobuf: Data(), bodyPlaintext: "updated", folderPath: "Notes")
        try await sut.recordAction(type: .edit, noteID: "n1", before: before, after: after, metadata: nil)

        // Undo should work
        let result = try await sut.undoLast()
        #expect(result != nil)
    }
}
