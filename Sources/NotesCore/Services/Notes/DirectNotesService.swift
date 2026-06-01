import Foundation

/// Unified facade implementing NotesServiceProtocol.
/// Reads are delegated to NoteStoreReader (direct SQLite access — fast).
/// Writes are delegated to AppleScriptWriter (NSAppleScript — required for Core Data / CloudKit integrity).
public final class DirectNotesService: NotesServiceProtocol, @unchecked Sendable {
    private let reader: NoteStoreReader
    private let writer: AppleScriptWriter
    let scope: Config.NotesScope

    public init(reader: NoteStoreReader, writer: AppleScriptWriter, scope: Config.NotesScope) {
        self.reader = reader
        self.writer = writer
        self.scope = scope
    }

    // MARK: - Refresh

    /// Copy the latest NoteStore.sqlite snapshot to the cache directory.
    /// Called automatically before read operations to ensure data is current.
    public func refresh() throws {
        try reader.refresh()
    }

    // MARK: - Read Operations (NoteStoreReader — SQLite, any thread)

    public func fetchAccountNames() async throws -> [String] {
        try reader.refresh()
        return try reader.fetchAccountNames()
    }

    public func fetchDefaultAccountName() async throws -> String? {
        try reader.refresh()
        return try reader.fetchDefaultAccountName()
    }

    public func fetchAllNoteMetadata() async throws -> [AppleNoteMetadata] {
        try reader.refresh()
        return try reader.fetchAllNoteMetadata()
            .filter { scope.isInSelectedAccount($0.folderPath) && !$0.isLocked }
    }

    public func fetchAllNotes() async throws -> [AppleNoteRaw] {
        try reader.refresh()
        return try reader.fetchAllNotes()
            .filter { scope.isInSelectedAccount($0.folderPath) && !$0.isLocked }
    }

    public func fetchNote(id: String) async throws -> AppleNoteRaw? {
        try reader.refresh()
        return try reader.fetchNote(id: id)
    }

    public func fetchFolders() async throws -> [AppleFolderRaw] {
        try reader.refresh()
        return try reader.fetchFolders().filter { scope.isInSelectedAccount($0.path) }
    }

    public func fetchAttachments(noteID: String) async throws -> [NoteAttachment] {
        try reader.refresh()
        return try reader.fetchAttachments(noteID: noteID)
    }

    // MARK: - Folder Path Helpers (pure logic, uses Config.NotesScope)

    public func scopedFolderPath(_ folderPath: String) -> String {
        scope.scopedFolderPath(folderPath)
    }

    public func resolvedFolderPath(_ folderPath: String?) -> String {
        scope.resolvedFolderPath(folderPath)
    }

    // MARK: - Availability

    /// Returns true if both the SQLite reader and AppleScript writer are available.
    public func isAvailable() async throws -> Bool {
        guard reader.isAvailable() else { return false }
        return try await writer.isAvailable()
    }

    // MARK: - Write Operations (AppleScriptWriter — @MainActor)

    public func createNote(title: String, bodyHTML: String, folderName: String) async throws -> String {
        try await writer.createNote(title: title, bodyHTML: bodyHTML, folderName: folderName)
    }

    public func updateNote(id: String, title: String?, bodyHTML: String?) async throws {
        try await writer.updateNote(id: id, title: title, bodyHTML: bodyHTML)
    }

    public func deleteNote(id: String) async throws {
        try await writer.deleteNote(id: id)
    }

    public func moveNote(id: String, toFolder folderName: String) async throws {
        try await writer.moveNote(id: id, toFolder: folderName)
    }

    public func createFolder(name: String, parentName: String?) async throws {
        try await writer.createFolder(name: name, parentName: parentName)
    }
}
