import NotesCore
import Foundation

enum NoteMutationSync {
    static func insertCreatedNote(
        id: String,
        title: String,
        bodyHTML: String,
        folderPath: String,
        notes: any NotesServiceProtocol,
        db: any DatabaseServiceProtocol
    ) async throws -> Note {
        let note: Note
        if let raw = try await notes.fetchNote(id: id) {
            note = Note(from: raw, syncedAt: Date())
        } else {
            note = Note(
                id: id,
                title: title,
                bodyProtobuf: Data(),
                bodyPlaintext: "",
                folderPath: notes.resolvedFolderPath(folderPath),
                syncedAt: Date()
            )
        }

        try await saveNoteInDatabase(note, db: db)
        return note
    }

    static func refreshExistingNote(
        id: String,
        fallback: Note,
        notes: any NotesServiceProtocol,
        db: any DatabaseServiceProtocol
    ) async throws -> Note {
        let note: Note
        if let raw = try await notes.fetchNote(id: id) {
            note = Note(from: raw, syncedAt: Date())
        } else {
            var refreshedFallback = fallback
            refreshedFallback.syncedAt = Date()
            note = refreshedFallback
        }

        try await saveNoteInDatabase(note, db: db)
        return note
    }

    private static func saveNoteInDatabase(_ note: Note, db: any DatabaseServiceProtocol) async throws {
        if try await db.fetchNote(id: note.id) != nil {
            try await db.updateNote(note)
        } else {
            try await db.insertNote(note)
        }
    }
}
