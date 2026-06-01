import Foundation

public protocol DatabaseServiceProtocol: Sendable {
    // MARK: - Notes
    func insertNote(_ note: Note) async throws
    func fetchNote(id: String) async throws -> Note?
    func fetchAllNotes() async throws -> [Note]
    func fetchNotes(inFolder folderPath: String) async throws -> [Note]
    func updateNote(_ note: Note) async throws
    func deleteNote(id: String) async throws

    // MARK: - Folders
    func insertFolder(_ folder: Folder) async throws
    func fetchFolder(path: String) async throws -> Folder?
    func fetchAllFolders() async throws -> [Folder]
    func updateFolder(_ folder: Folder) async throws
    func deleteFolder(path: String) async throws

    // MARK: - Tags
    func insertTag(_ tag: Tag) async throws -> Tag
    func fetchTag(name: String) async throws -> Tag?
    func fetchAllTags() async throws -> [Tag]
    func deleteTag(id: Int64) async throws

    // MARK: - Note-Tag Associations
    func addTag(noteID: String, tagID: Int64) async throws
    func removeTag(noteID: String, tagID: Int64) async throws
    func fetchTags(forNoteID noteID: String) async throws -> [Tag]
    func fetchNotes(forTagID tagID: Int64) async throws -> [Note]

    // MARK: - Links
    func insertLink(_ link: Link) async throws -> Link
    func fetchLinks(fromNoteID noteID: String) async throws -> [Link]
    func fetchLinks(toNoteID noteID: String) async throws -> [Link]
    func deleteLink(sourceNoteID: String, targetNoteID: String) async throws

    // MARK: - Action Records
    func insertActionRecord(_ record: ActionRecord) async throws -> ActionRecord
    func fetchActionRecords(forNoteID noteID: String) async throws -> [ActionRecord]
    func fetchLatestActionRecord() async throws -> ActionRecord?
    func fetchLatestUndoableAction() async throws -> ActionRecord?
    func fetchAllActionRecords(limit: Int) async throws -> [ActionRecord]
    func updateActionRecord(_ record: ActionRecord) async throws

    // MARK: - Sync State
    func setSyncState(key: String, value: String) async throws
    func getSyncState(key: String) async throws -> String?

    // MARK: - Note Attachments
    func insertAttachment(_ attachment: NoteAttachment) async throws
    func fetchAttachments(forNoteID noteID: String) async throws -> [NoteAttachment]
    func deleteAttachments(forNoteID noteID: String) async throws

    // MARK: - FTS5 Search
    func searchNotes(query: String) async throws -> [Note]
}
