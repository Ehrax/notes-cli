import Foundation
import GRDB

extension DatabaseService {
    // MARK: - Note Attachments

    public func insertAttachment(_ attachment: NoteAttachment) async throws {
        try await dbQueue.write { database in
            try attachment.insert(database)
        }
    }

    public func fetchAttachments(forNoteID noteID: String) async throws -> [NoteAttachment] {
        try await dbQueue.read { database in
            try NoteAttachment.filter(Column("noteID") == noteID).fetchAll(database)
        }
    }

    public func deleteAttachments(forNoteID noteID: String) async throws {
        try await dbQueue.write { database in
            _ = try NoteAttachment.filter(Column("noteID") == noteID).deleteAll(database)
        }
    }

    // MARK: - Additional Note Queries

    public func fetchNotes(inFolder folderPath: String) async throws -> [Note] {
        try await dbQueue.read { database in
            try Note.filter(Column("folderPath") == folderPath)
                .order(Column("modificationDate").desc)
                .fetchAll(database)
        }
    }

    public func fetchNotes(modifiedAfter date: Date) async throws -> [Note] {
        try await dbQueue.read { database in
            try Note.filter(Column("modificationDate") > date)
                .order(Column("modificationDate").desc)
                .fetchAll(database)
        }
    }

    public func fetchNotes(withChecksum checksum: String) async throws -> [Note] {
        try await dbQueue.read { database in
            try Note.filter(Column("checksum") == checksum).fetchAll(database)
        }
    }

    public func fetchNoteCount(inFolder folderPath: String) async throws -> Int {
        try await dbQueue.read { database in
            try Note.filter(Column("folderPath") == folderPath).fetchCount(database)
        }
    }
}
