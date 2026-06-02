import Foundation

/// Protocol for interacting with Apple Notes.
public protocol NotesServiceProtocol: Sendable {
    func fetchAccountNames() async throws -> [String]
    func fetchDefaultAccountName() async throws -> String?
    func scopedFolderPath(_ folderPath: String) -> String
    func resolvedFolderPath(_ folderPath: String?) -> String
    func fetchAllNoteMetadata() async throws -> [AppleNoteMetadata]
    func fetchAllNotes() async throws -> [AppleNoteRaw]
    func searchNotes(query: String, limit: Int) async throws -> [AppleNoteRaw]
    func fetchNote(id: String) async throws -> AppleNoteRaw?
    func createNote(title: String, bodyHTML: String, folderName: String) async throws -> String
    func updateNote(id: String, title: String?, bodyHTML: String?) async throws
    func deleteNote(id: String) async throws
    func moveNote(id: String, toFolder folderName: String) async throws
    func fetchFolders() async throws -> [AppleFolderRaw]
    func fetchAttachments(noteID: String) async throws -> [NoteAttachment]
    func createFolder(name: String, parentName: String?) async throws
    func renameFolder(path: String, newName: String) async throws
    func deleteFolder(path: String) async throws
    func moveFolder(path: String, toParent parentPath: String?) async throws
    func isAvailable() async throws -> Bool
}
