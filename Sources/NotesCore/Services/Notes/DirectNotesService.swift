import Foundation

/// Unified facade implementing NotesServiceProtocol.
/// Reads are delegated to NoteStoreReader (direct SQLite access — fast).
/// Writes are delegated to ScriptingBridgeWriter (ScriptingBridge — the single write path).
public final class DirectNotesService: NotesServiceProtocol, @unchecked Sendable {
    private let reader: NoteStoreReader
    private let writer: ScriptingBridgeWriter
    let scope: Config.NotesScope
    private let aiFooterEnabled: Bool

    public init(
        reader: NoteStoreReader,
        writer: ScriptingBridgeWriter,
        scope: Config.NotesScope,
        aiFooterEnabled: Bool = true
    ) {
        self.reader = reader
        self.writer = writer
        self.scope = scope
        self.aiFooterEnabled = aiFooterEnabled
    }

    /// Environment variable the calling agent/harness sets to identify the model in the footer.
    static let agentEnvVar = "NOTES_CLI_AGENT"

    // MARK: - Read Operations (NoteStoreReader — SQLite, any thread)

    public func fetchAccountNames() async throws -> [String] {
        try reader.fetchAccountNames()
    }

    public func fetchDefaultAccountName() async throws -> String? {
        try reader.fetchDefaultAccountName()
    }

    public func fetchAllNoteMetadata() async throws -> [AppleNoteMetadata] {
        try reader.fetchAllNoteMetadata()
            .filter { scope.isInSelectedAccount($0.folderPath) && !$0.isLocked }
    }

    public func fetchAllNotes() async throws -> [AppleNoteRaw] {
        try reader.fetchAllNotes()
            .filter { scope.isInSelectedAccount($0.folderPath) && !$0.isLocked }
    }

    public func searchNotes(query: String, limit: Int) async throws -> [AppleNoteRaw] {
        NoteSearch.rank(notes: try await fetchAllNotes(), query: query, limit: limit)
    }

    public func fetchNote(id: String) async throws -> AppleNoteRaw? {
        try reader.fetchNote(id: id)
    }

    public func fetchFolders() async throws -> [AppleFolderRaw] {
        try reader.fetchFolders().filter { scope.isInSelectedAccount($0.path) }
    }

    public func fetchAttachments(noteID: String) async throws -> [NoteAttachment] {
        try reader.fetchAttachments(noteID: noteID)
    }

    // MARK: - Folder Path Helpers (pure logic, uses Config.NotesScope)

    public func scopedFolderPath(_ folderPath: String) -> String {
        scope.scopedFolderPath(folderPath)
    }

    public func resolvedFolderPath(_ folderPath: String?) -> String {
        scope.resolvedFolderPath(folderPath)
    }

    // MARK: - Availability

    /// Returns true if both the SQLite reader and the ScriptingBridge writer are available.
    public func isAvailable() async throws -> Bool {
        guard reader.isAvailable() else { return false }
        return try await writer.isAvailable()
    }

    // MARK: - Write Operations (ScriptingBridgeWriter — @MainActor)

    public func createNote(title: String, bodyHTML: String, folderName: String, agent: String?) async throws -> String {
        var body = bodyHTML
        if aiFooterEnabled {
            let model = agent ?? ProcessInfo.processInfo.environment[Self.agentEnvVar]
            body += NoteHTML.footer(model: model)
        }
        return try await writer.createNote(title: title, bodyHTML: body, folderName: folderName)
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

    public func renameFolder(path: String, newName: String) async throws {
        try await writer.renameFolder(path: path, newName: newName)
    }

    public func deleteFolder(path: String) async throws {
        try await writer.deleteFolder(path: path)
    }

    public func moveFolder(path: String, toParent parentPath: String?) async throws {
        try await writer.moveFolder(path: path, toParent: parentPath)
    }
}
