import Foundation
import NotesCore

/// A simple in-memory mock of DatabaseServiceProtocol for testing.
public final class MockDatabaseService: DatabaseServiceProtocol, @unchecked Sendable {
    public var notes: [String: Note] = [:]
    public var folders: [String: Folder] = [:]
    public var tags: [Int64: Tag] = [:]
    public var noteTags: [(noteID: String, tagID: Int64)] = []
    public var links: [Link] = []
    public var actionRecords: [ActionRecord] = []
    public var syncState: [String: String] = [:]
    public var noteInsertFailures: Set<String> = []
    public var noteUpdateFailures: Set<String> = []
    public var noteDeleteFailures: Set<String> = []
    public var failAllNoteInserts = false
    public var strictMissingNoteUpdates = false
    public var actionRecordInsertError: Error?
    private var nextTagID: Int64 = 1
    private var nextLinkID: Int64 = 1
    private var nextActionID: Int64 = 1

    public init() {}

    // MARK: - Notes
    public func insertNote(_ note: Note) async throws {
        if failAllNoteInserts {
            throw NotesError.commandFailed(message: "insert failed for \(note.id)")
        }
        if noteInsertFailures.contains(note.id) {
            throw NotesError.commandFailed(message: "insert failed for \(note.id)")
        }
        notes[note.id] = note
    }
    public func fetchNote(id: String) async throws -> Note? { notes[id] }
    public func fetchAllNotes() async throws -> [Note] { Array(notes.values) }
    public func fetchNotes(inFolder folderPath: String) async throws -> [Note] {
        notes.values.filter { $0.folderPath == folderPath }
    }
    public func updateNote(_ note: Note) async throws {
        if noteUpdateFailures.contains(note.id) {
            throw NotesError.commandFailed(message: "update failed for \(note.id)")
        }
        if strictMissingNoteUpdates, notes[note.id] == nil {
            throw NotesError.commandFailed(message: "note not found for update \(note.id)")
        }
        notes[note.id] = note
    }
    public func deleteNote(id: String) async throws {
        if noteDeleteFailures.contains(id) {
            throw NotesError.commandFailed(message: "delete failed for \(id)")
        }
        notes.removeValue(forKey: id)
    }

    // MARK: - Folders
    public func insertFolder(_ folder: Folder) async throws {
        folders = folders.filter { $0.value.id != folder.id }
        folders[folder.path] = folder
    }
    public func fetchFolder(path: String) async throws -> Folder? { folders[path] }
    public func fetchAllFolders() async throws -> [Folder] { Array(folders.values) }
    public func updateFolder(_ folder: Folder) async throws {
        folders = folders.filter { $0.value.id != folder.id }
        folders[folder.path] = folder
    }
    public func deleteFolder(path: String) async throws { folders.removeValue(forKey: path) }

    // MARK: - Tags
    public func insertTag(_ tag: Tag) async throws -> Tag {
        var t = tag
        t.id = nextTagID
        nextTagID += 1
        tags[t.id!] = t
        return t
    }
    public func fetchTag(name: String) async throws -> Tag? { tags.values.first { $0.name == name } }
    public func fetchAllTags() async throws -> [Tag] { Array(tags.values) }
    public func deleteTag(id: Int64) async throws { tags.removeValue(forKey: id) }

    // MARK: - Note-Tag
    public func addTag(noteID: String, tagID: Int64) async throws { noteTags.append((noteID, tagID)) }
    public func removeTag(noteID: String, tagID: Int64) async throws {
        noteTags.removeAll { $0.noteID == noteID && $0.tagID == tagID }
    }
    public func fetchTags(forNoteID noteID: String) async throws -> [Tag] {
        noteTags.filter { $0.noteID == noteID }.compactMap { tags[$0.tagID] }
    }
    public func fetchNotes(forTagID tagID: Int64) async throws -> [Note] {
        noteTags.filter { $0.tagID == tagID }.compactMap { notes[$0.noteID] }
    }

    // MARK: - Links
    public func insertLink(_ link: Link) async throws -> Link {
        var l = link
        l.id = nextLinkID
        nextLinkID += 1
        links.append(l)
        return l
    }
    public func fetchLinks(fromNoteID noteID: String) async throws -> [Link] {
        links.filter { $0.sourceNoteID == noteID }
    }
    public func fetchLinks(toNoteID noteID: String) async throws -> [Link] {
        links.filter { $0.targetNoteID == noteID }
    }
    public func deleteLink(sourceNoteID: String, targetNoteID: String) async throws {
        links.removeAll { $0.sourceNoteID == sourceNoteID && $0.targetNoteID == targetNoteID }
    }

    // MARK: - Action Records
    public func insertActionRecord(_ record: ActionRecord) async throws -> ActionRecord {
        if let actionRecordInsertError {
            throw actionRecordInsertError
        }
        var r = record
        r.id = nextActionID
        nextActionID += 1
        actionRecords.append(r)
        return r
    }
    public func fetchActionRecords(forNoteID noteID: String) async throws -> [ActionRecord] {
        if noteID.isEmpty {
            return actionRecords
        }
        return actionRecords.filter { $0.noteID == noteID }
    }
    public func fetchLatestActionRecord() async throws -> ActionRecord? {
        actionRecords.max { $0.timestamp < $1.timestamp }
    }
    public func fetchLatestUndoableAction() async throws -> ActionRecord? {
        actionRecords.filter { !$0.undone }.max { $0.timestamp < $1.timestamp }
    }
    public func fetchAllActionRecords(limit: Int) async throws -> [ActionRecord] {
        Array(actionRecords.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }
    public func updateActionRecord(_ record: ActionRecord) async throws {
        if let idx = actionRecords.firstIndex(where: { $0.id == record.id }) {
            actionRecords[idx] = record
        }
    }

    // MARK: - Sync State
    public func setSyncState(key: String, value: String) async throws { syncState[key] = value }
    public func getSyncState(key: String) async throws -> String? { syncState[key] }

    // MARK: - Note Attachments
    public var attachments: [String: [NoteAttachment]] = [:]

    public func insertAttachment(_ attachment: NoteAttachment) async throws {
        attachments[attachment.noteID, default: []].append(attachment)
    }

    public func fetchAttachments(forNoteID noteID: String) async throws -> [NoteAttachment] {
        attachments[noteID] ?? []
    }

    public func deleteAttachments(forNoteID noteID: String) async throws {
        attachments.removeValue(forKey: noteID)
    }

    // MARK: - Search
    public func searchNotes(query: String) async throws -> [Note] {
        notes.values.filter { $0.title.contains(query) || $0.bodyPlaintext.contains(query) }
    }
}
