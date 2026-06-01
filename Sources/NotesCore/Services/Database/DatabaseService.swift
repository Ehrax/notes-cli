import Foundation
import GRDB

public final class DatabaseService: DatabaseServiceProtocol, Sendable {
    let dbQueue: DatabaseQueue

    public init(path: String = ":memory:") throws {
        if path == ":memory:" {
            dbQueue = try DatabaseQueue()
        } else {
            dbQueue = try DatabaseQueue(path: path)
        }
        Log.info("[db] opened path=\"\(path)\"", logger: Log.database)

        var migrator = DatabaseMigrator()
        NotesCLIMigrations.registerAll(in: &migrator)
        try migrator.migrate(dbQueue)
        Log.info("[db] migrations_applied count=\(NotesCLIMigrations.migrationNames.count)", logger: Log.database)
    }

    // MARK: - Notes

    public func insertNote(_ note: Note) async throws {
        try await dbQueue.write { database in
            try note.insert(database)
        }
    }

    public func fetchNote(id: String) async throws -> Note? {
        try await dbQueue.read { database in
            try Note.fetchOne(database, key: id)
        }
    }

    public func fetchAllNotes() async throws -> [Note] {
        try await dbQueue.read { database in
            try Note.fetchAll(database)
        }
    }

    public func updateNote(_ note: Note) async throws {
        try await dbQueue.write { database in
            try note.update(database)
        }
    }

    public func deleteNote(id: String) async throws {
        try await dbQueue.write { database in
            _ = try Note.deleteOne(database, key: id)
        }
    }

    // MARK: - Folders

    public func insertFolder(_ folder: Folder) async throws {
        try await dbQueue.write { database in
            try folder.insert(database)
        }
    }

    public func fetchFolder(path: String) async throws -> Folder? {
        try await dbQueue.read { database in
            try Folder.filter(Column("path") == path).fetchOne(database)
        }
    }

    public func fetchAllFolders() async throws -> [Folder] {
        try await dbQueue.read { database in
            try Folder.fetchAll(database)
        }
    }

    public func updateFolder(_ folder: Folder) async throws {
        try await dbQueue.write { database in
            try folder.update(database)
        }
    }

    public func deleteFolder(path: String) async throws {
        try await dbQueue.write { database in
            _ = try Folder.filter(Column("path") == path).deleteAll(database)
        }
    }

    // MARK: - Tags

    public func insertTag(_ tag: Tag) async throws -> Tag {
        try await dbQueue.write { database in
            var mutableTag = tag
            try mutableTag.insert(database)
            return mutableTag
        }
    }

    public func fetchTag(name: String) async throws -> Tag? {
        try await dbQueue.read { database in
            try Tag.filter(Column("name") == name).fetchOne(database)
        }
    }

    public func fetchAllTags() async throws -> [Tag] {
        try await dbQueue.read { database in
            try Tag.fetchAll(database)
        }
    }

    public func deleteTag(id: Int64) async throws {
        try await dbQueue.write { database in
            _ = try Tag.deleteOne(database, key: id)
        }
    }

    // MARK: - Note-Tag Associations

    public func addTag(noteID: String, tagID: Int64) async throws {
        try await dbQueue.write { database in
            let noteTag = NoteTag(noteID: noteID, tagID: tagID)
            try noteTag.insert(database)
        }
    }

    public func removeTag(noteID: String, tagID: Int64) async throws {
        try await dbQueue.write { database in
            _ = try NoteTag
                .filter(Column("noteID") == noteID && Column("tagID") == tagID)
                .deleteAll(database)
        }
    }

    public func fetchTags(forNoteID noteID: String) async throws -> [Tag] {
        try await dbQueue.read { database in
            let sql = """
                SELECT tag.* FROM tag
                JOIN noteTag ON noteTag.tagID = tag.id
                WHERE noteTag.noteID = ?
                """
            return try Tag.fetchAll(database, sql: sql, arguments: [noteID])
        }
    }

    public func fetchNotes(forTagID tagID: Int64) async throws -> [Note] {
        try await dbQueue.read { database in
            let sql = """
                SELECT note.* FROM note
                JOIN noteTag ON noteTag.noteID = note.id
                WHERE noteTag.tagID = ?
                """
            return try Note.fetchAll(database, sql: sql, arguments: [tagID])
        }
    }

    // MARK: - Links

    public func insertLink(_ link: Link) async throws -> Link {
        try await dbQueue.write { database in
            var mutableLink = link
            try mutableLink.insert(database)
            return mutableLink
        }
    }

    public func fetchLinks(fromNoteID noteID: String) async throws -> [Link] {
        try await dbQueue.read { database in
            try Link.filter(Column("sourceNoteID") == noteID).fetchAll(database)
        }
    }

    public func fetchLinks(toNoteID noteID: String) async throws -> [Link] {
        try await dbQueue.read { database in
            try Link.filter(Column("targetNoteID") == noteID).fetchAll(database)
        }
    }

    public func deleteLink(sourceNoteID: String, targetNoteID: String) async throws {
        try await dbQueue.write { database in
            _ = try Link
                .filter(
                    Column("sourceNoteID") == sourceNoteID
                        && Column("targetNoteID") == targetNoteID
                )
                .deleteAll(database)
        }
    }

    // MARK: - Action Records

    public func insertActionRecord(_ record: ActionRecord) async throws -> ActionRecord {
        try await dbQueue.write { database in
            var mutableRecord = record
            try mutableRecord.insert(database)
            return mutableRecord
        }
    }

    public func fetchActionRecords(forNoteID noteID: String) async throws -> [ActionRecord] {
        try await dbQueue.read { database in
            try ActionRecord.filter(Column("noteID") == noteID)
                .order(Column("timestamp").desc)
                .fetchAll(database)
        }
    }

    public func fetchLatestActionRecord() async throws -> ActionRecord? {
        try await dbQueue.read { database in
            try ActionRecord.order(Column("timestamp").desc).fetchOne(database)
        }
    }

    public func fetchLatestUndoableAction() async throws -> ActionRecord? {
        try await dbQueue.read { database in
            try ActionRecord
                .filter(Column("undone") == false)
                .order(Column("timestamp").desc)
                .fetchOne(database)
        }
    }

    public func fetchAllActionRecords(limit: Int) async throws -> [ActionRecord] {
        try await dbQueue.read { database in
            try ActionRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(database)
        }
    }

    public func updateActionRecord(_ record: ActionRecord) async throws {
        try await dbQueue.write { database in
            try record.update(database)
        }
    }

    // MARK: - Sync State

    public func setSyncState(key: String, value: String) async throws {
        try await dbQueue.write { database in
            let state = SyncState(key: key, value: value)
            try state.save(database)
        }
    }

    public func getSyncState(key: String) async throws -> String? {
        try await dbQueue.read { database in
            let state = try SyncState.fetchOne(database, key: key)
            return state?.value
        }
    }
}
