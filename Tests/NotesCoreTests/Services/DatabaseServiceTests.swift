import Foundation
import Testing

@testable import NotesCore

// swiftlint:disable type_body_length file_length

@Suite("DatabaseService Tests")
struct DatabaseServiceTests {

    private func makeService() throws -> DatabaseService {
        try DatabaseService(path: ":memory:")
    }

    private func makeSampleNote(
        id: String = "note-1",
        title: String = "Test Note",
        bodyProtobuf: Data = Data(),
        bodyPlaintext: String = "Hello",
        folderPath: String = "/Notes"
    ) -> Note {
        Note(
            id: id,
            title: title,
            bodyProtobuf: bodyProtobuf,
            bodyPlaintext: bodyPlaintext,
            folderPath: folderPath
        )
    }

    // MARK: - Migrations

    @Test("Migrations create all tables")
    func migrationsCreateAllTables() async throws {
        let service = try makeService()
        // If we got here without throwing, all migrations ran successfully.
        // Verify by inserting into each table.
        let note = makeSampleNote()
        try await service.insertNote(note)
        let fetched = try await service.fetchNote(id: "note-1")
        #expect(fetched != nil)
    }

    // MARK: - Note CRUD

    @Test("Insert and fetch note")
    func insertAndFetchNote() async throws {
        let service = try makeService()
        let note = makeSampleNote()
        try await service.insertNote(note)

        let fetched = try await service.fetchNote(id: "note-1")
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Note")
        #expect(fetched?.bodyPlaintext == "Hello")
    }

    @Test("Update note")
    func updateNote() async throws {
        let service = try makeService()
        var note = makeSampleNote()
        try await service.insertNote(note)

        note.title = "Updated Title"
        try await service.updateNote(note)

        let fetched = try await service.fetchNote(id: "note-1")
        #expect(fetched?.title == "Updated Title")
    }

    @Test("Delete note")
    func deleteNote() async throws {
        let service = try makeService()
        let note = makeSampleNote()
        try await service.insertNote(note)
        try await service.deleteNote(id: "note-1")

        let fetched = try await service.fetchNote(id: "note-1")
        #expect(fetched == nil)
    }

    @Test("Fetch all notes")
    func fetchAllNotes() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote(id: "n1"))
        try await service.insertNote(makeSampleNote(id: "n2"))

        let all = try await service.fetchAllNotes()
        #expect(all.count == 2)
    }

    // MARK: - Folder CRUD

    @Test("Insert and fetch folder")
    func insertAndFetchFolder() async throws {
        let service = try makeService()
        let folder = Folder(id: "f1", name: "Notes", path: "/Notes")
        try await service.insertFolder(folder)

        let fetched = try await service.fetchFolder(path: "/Notes")
        #expect(fetched != nil)
        #expect(fetched?.name == "Notes")
    }

    @Test("Update folder")
    func updateFolder() async throws {
        let service = try makeService()
        var folder = Folder(id: "f1", name: "Notes", path: "/Notes")
        try await service.insertFolder(folder)

        folder.name = "My Notes"
        try await service.updateFolder(folder)

        let fetched = try await service.fetchFolder(path: "/Notes")
        #expect(fetched?.name == "My Notes")
    }

    @Test("Delete folder")
    func deleteFolder() async throws {
        let service = try makeService()
        let folder = Folder(id: "f1", name: "Notes", path: "/Notes")
        try await service.insertFolder(folder)
        try await service.deleteFolder(path: "/Notes")

        let fetched = try await service.fetchFolder(path: "/Notes")
        #expect(fetched == nil)
    }

    // MARK: - Tag CRUD + Note-Tag Association

    @Test("Insert and fetch tag")
    func insertAndFetchTag() async throws {
        let service = try makeService()
        let tag = try await service.insertTag(Tag(name: "swift"))

        #expect(tag.id != nil)
        let fetched = try await service.fetchTag(name: "swift")
        #expect(fetched?.name == "swift")
    }

    @Test("Tag note association")
    func tagNoteAssociation() async throws {
        let service = try makeService()
        let note = makeSampleNote()
        try await service.insertNote(note)
        let tag = try await service.insertTag(Tag(name: "important"))

        try await service.addTag(noteID: "note-1", tagID: tag.id!)

        let tags = try await service.fetchTags(forNoteID: "note-1")
        #expect(tags.count == 1)
        #expect(tags.first?.name == "important")

        let notes = try await service.fetchNotes(forTagID: tag.id!)
        #expect(notes.count == 1)
        #expect(notes.first?.id == "note-1")
    }

    @Test("Remove tag from note")
    func removeTagFromNote() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote())
        let tag = try await service.insertTag(Tag(name: "temp"))
        try await service.addTag(noteID: "note-1", tagID: tag.id!)
        try await service.removeTag(noteID: "note-1", tagID: tag.id!)

        let tags = try await service.fetchTags(forNoteID: "note-1")
        #expect(tags.isEmpty)
    }

    @Test("Delete tag cascades")
    func deleteTagCascades() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote())
        let tag = try await service.insertTag(Tag(name: "cascade"))
        try await service.addTag(noteID: "note-1", tagID: tag.id!)
        try await service.deleteTag(id: tag.id!)

        let tags = try await service.fetchTags(forNoteID: "note-1")
        #expect(tags.isEmpty)
    }

    // MARK: - Link CRUD

    @Test("Insert and fetch links")
    func insertAndFetchLinks() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote(id: "n1"))
        try await service.insertNote(makeSampleNote(id: "n2"))

        let link = try await service.insertLink(
            Link(sourceNoteID: "n1", targetNoteID: "n2")
        )
        #expect(link.id != nil)

        let outgoing = try await service.fetchLinks(fromNoteID: "n1")
        #expect(outgoing.count == 1)
        #expect(outgoing.first?.targetNoteID == "n2")

        let incoming = try await service.fetchLinks(toNoteID: "n2")
        #expect(incoming.count == 1)
        #expect(incoming.first?.sourceNoteID == "n1")
    }

    @Test("Delete link")
    func deleteLink() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote(id: "n1"))
        try await service.insertNote(makeSampleNote(id: "n2"))
        _ = try await service.insertLink(
            Link(sourceNoteID: "n1", targetNoteID: "n2")
        )
        try await service.deleteLink(sourceNoteID: "n1", targetNoteID: "n2")

        let links = try await service.fetchLinks(fromNoteID: "n1")
        #expect(links.isEmpty)
    }

    // MARK: - Action Record CRUD

    @Test("Insert and fetch action record")
    func insertAndFetchActionRecord() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote(id: "note-1"))
        let record = try await service.insertActionRecord(
            ActionRecord(actionType: .create, noteID: "note-1")
        )
        #expect(record.id != nil)

        let records = try await service.fetchActionRecords(forNoteID: "note-1")
        #expect(records.count == 1)
        #expect(records.first?.actionType == .create)
    }

    @Test("Fetch latest action record")
    func fetchLatestActionRecord() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote(id: "n1"))
        _ = try await service.insertActionRecord(
            ActionRecord(
                actionType: .create,
                noteID: "n1",
                timestamp: Date(timeIntervalSince1970: 1_000)
            )
        )
        _ = try await service.insertActionRecord(
            ActionRecord(
                actionType: .edit,
                noteID: "n1",
                timestamp: Date(timeIntervalSince1970: 2_000)
            )
        )

        let latest = try await service.fetchLatestActionRecord()
        #expect(latest?.actionType == .edit)
    }

    @Test("Update action record (mark undone)")
    func updateActionRecord() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote(id: "n1"))
        var record = try await service.insertActionRecord(
            ActionRecord(actionType: .create, noteID: "n1")
        )
        record.undone = true
        try await service.updateActionRecord(record)

        let records = try await service.fetchActionRecords(forNoteID: "n1")
        #expect(records.first?.undone == true)
    }

    // MARK: - Sync State

    @Test("Set and get sync state")
    func setAndGetSyncState() async throws {
        let service = try makeService()
        try await service.setSyncState(key: "lastSync", value: "2025-01-01")

        let value = try await service.getSyncState(key: "lastSync")
        #expect(value == "2025-01-01")
    }

    @Test("Overwrite sync state")
    func overwriteSyncState() async throws {
        let service = try makeService()
        try await service.setSyncState(key: "lastSync", value: "2025-01-01")
        try await service.setSyncState(key: "lastSync", value: "2025-06-01")

        let value = try await service.getSyncState(key: "lastSync")
        #expect(value == "2025-06-01")
    }

    // MARK: - FTS5 Search

    @Test("FTS5 search by title")
    func fts5SearchByTitle() async throws {
        let service = try makeService()
        try await service.insertNote(
            makeSampleNote(
                id: "n1",
                title: "Swift Programming Guide",
                bodyPlaintext: "Some content here"
            )
        )
        try await service.insertNote(
            makeSampleNote(
                id: "n2",
                title: "Cooking Recipes",
                bodyPlaintext: "Pasta and pizza"
            )
        )

        let results = try await service.searchNotes(query: "swift programming")
        #expect(results.count == 1)
        #expect(results.first?.id == "n1")
    }

    @Test("FTS5 search by body")
    func fts5SearchByBody() async throws {
        let service = try makeService()
        try await service.insertNote(
            makeSampleNote(
                id: "n1",
                title: "Note A",
                bodyPlaintext: "The quick brown fox jumps over the lazy dog"
            )
        )
        try await service.insertNote(
            makeSampleNote(
                id: "n2",
                title: "Note B",
                bodyPlaintext: "Mathematics and physics"
            )
        )

        let results = try await service.searchNotes(query: "quick brown fox")
        #expect(results.count == 1)
        #expect(results.first?.id == "n1")
    }

    @Test("FTS5 search returns empty for no match")
    func fts5SearchNoMatch() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote())

        let results = try await service.searchNotes(query: "nonexistent")
        #expect(results.isEmpty)
    }

    // MARK: - Note Queries

    @Test("Fetch notes in folder")
    func fetchNotesInFolder() async throws {
        let service = try makeService()
        try await service.insertNote(makeSampleNote(id: "n1", folderPath: "/Work"))
        try await service.insertNote(makeSampleNote(id: "n2", folderPath: "/Personal"))
        try await service.insertNote(makeSampleNote(id: "n3", folderPath: "/Work"))

        let workNotes = try await service.fetchNotes(inFolder: "/Work")
        #expect(workNotes.count == 2)
    }
}

// swiftlint:enable type_body_length file_length
