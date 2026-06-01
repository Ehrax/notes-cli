import Foundation
import Testing
import NotesCore
import NotesTestSupport

@Suite("Database Integration Tests")
struct DatabaseIntegrationTests {

    // MARK: - Tag + note association and query

    @Test("Tag and note association works through real DB joins")
    func tagNoteAssociationAndQuery() async throws {
        let db = try makeRealDatabase()

        let note1 = makeSampleNote(id: "n1", title: "Swift Guide")
        let note2 = makeSampleNote(id: "n2", title: "Cooking Tips")
        let note3 = makeSampleNote(id: "n3", title: "Swift Tips")

        try await db.insertNote(note1)
        try await db.insertNote(note2)
        try await db.insertNote(note3)

        let swiftTag = try await db.insertTag(Tag(name: "swift"))
        let cookingTag = try await db.insertTag(Tag(name: "cooking"))

        try await db.addTag(noteID: "n1", tagID: swiftTag.id!)
        try await db.addTag(noteID: "n3", tagID: swiftTag.id!)
        try await db.addTag(noteID: "n2", tagID: cookingTag.id!)

        // Query notes by tag
        let swiftNotes = try await db.fetchNotes(forTagID: swiftTag.id!)
        #expect(swiftNotes.count == 2)
        let swiftNoteIDs = Set(swiftNotes.map(\.id))
        #expect(swiftNoteIDs == ["n1", "n3"])

        let cookingNotes = try await db.fetchNotes(forTagID: cookingTag.id!)
        #expect(cookingNotes.count == 1)
        #expect(cookingNotes.first?.id == "n2")

        // Query tags by note
        let n1Tags = try await db.fetchTags(forNoteID: "n1")
        #expect(n1Tags.count == 1)
        #expect(n1Tags.first?.name == "swift")
    }

    // MARK: - Bidirectional links

    @Test("Bidirectional link queries work through real DB")
    func bidirectionalLinks() async throws {
        let db = try makeRealDatabase()

        try await db.insertNote(makeSampleNote(id: "n1", title: "Note A"))
        try await db.insertNote(makeSampleNote(id: "n2", title: "Note B"))
        try await db.insertNote(makeSampleNote(id: "n3", title: "Note C"))

        _ = try await db.insertLink(Link(sourceNoteID: "n1", targetNoteID: "n2"))
        _ = try await db.insertLink(Link(sourceNoteID: "n1", targetNoteID: "n3"))
        _ = try await db.insertLink(Link(sourceNoteID: "n2", targetNoteID: "n3"))

        // Outgoing from n1
        let outgoing = try await db.fetchLinks(fromNoteID: "n1")
        #expect(outgoing.count == 2)
        let outTargets = Set(outgoing.map(\.targetNoteID))
        #expect(outTargets == ["n2", "n3"])

        // Incoming to n3
        let incoming = try await db.fetchLinks(toNoteID: "n3")
        #expect(incoming.count == 2)
        let inSources = Set(incoming.map(\.sourceNoteID))
        #expect(inSources == ["n1", "n2"])

        // Incoming to n2
        let incomingN2 = try await db.fetchLinks(toNoteID: "n2")
        #expect(incomingN2.count == 1)
        #expect(incomingN2.first?.sourceNoteID == "n1")
    }

    // MARK: - FTS search with special characters

    @Test("FTS search handles accented and special characters")
    func ftsSearchSpecialCharacters() async throws {
        let db = try makeRealDatabase()

        try await db.insertNote(makeSampleNote(
            id: "n1", title: "C++ Programming",
            bodyPlaintext: "pointers and references"
        ))
        try await db.insertNote(makeSampleNote(
            id: "n2", title: "Résumé Writing Tips",
            bodyPlaintext: "How to write a great resume"
        ))
        try await db.insertNote(makeSampleNote(
            id: "n3", title: "Café Guide",
            bodyPlaintext: "Best cafes with naïve charm and über style"
        ))

        // Search by body content with plain words
        let pointerResults = try await db.searchNotes(query: "pointers")
        #expect(pointerResults.count == 1)
        #expect(pointerResults.first?.id == "n1")

        // Unicode61 tokenizer normalizes accents, so "resume" should find "Résumé"
        let resumeResults = try await db.searchNotes(query: "resume")
        #expect(resumeResults.count == 1)
        #expect(resumeResults.first?.id == "n2")

        // Search for stemmed word (porter tokenizer: "cafes" -> "cafe")
        let cafeResults = try await db.searchNotes(query: "cafe")
        #expect(cafeResults.count >= 1)
        let cafeIDs = Set(cafeResults.map(\.id))
        #expect(cafeIDs.contains("n3"))
    }

    // MARK: - Action record insert and fetchLatestUndoableAction

    @Test("Action records: insert multiple, mark some undone, latest undoable is correct")
    func actionRecordInsertAndFetchLatestUndoable() async throws {
        let db = try makeRealDatabase()

        // Insert a note first (FK constraint)
        try await db.insertNote(makeSampleNote(id: "n1"))

        // Insert multiple action records
        var r1 = try await db.insertActionRecord(
            ActionRecord(actionType: .create, noteID: "n1", timestamp: Date(timeIntervalSince1970: 1000))
        )
        let r2 = try await db.insertActionRecord(
            ActionRecord(actionType: .edit, noteID: "n1", timestamp: Date(timeIntervalSince1970: 2000))
        )
        _ = try await db.insertActionRecord(
            ActionRecord(actionType: .edit, noteID: "n1", timestamp: Date(timeIntervalSince1970: 3000))
        )

        // Mark r1 as undone
        r1.undone = true
        try await db.updateActionRecord(r1)

        // Latest undoable should be the most recent non-undone action (r3 at t=3000)
        let latest = try await db.fetchLatestUndoableAction()
        #expect(latest != nil)
        #expect(latest?.timestamp == Date(timeIntervalSince1970: 3000))
        #expect(latest?.undone == false)

        // Fetch all records
        let all = try await db.fetchAllActionRecords(limit: 10)
        #expect(all.count == 3)

        // Verify order (newest first)
        #expect(all[0].timestamp == Date(timeIntervalSince1970: 3000))
        #expect(all[2].timestamp == Date(timeIntervalSince1970: 1000))

        // Verify r2 is still not undone
        let r2Fetched = all.first { $0.id == r2.id }
        #expect(r2Fetched?.undone == false)
    }
}
