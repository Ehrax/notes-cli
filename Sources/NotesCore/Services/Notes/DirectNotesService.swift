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
            .filter(isVisible)
    }

    public func fetchAllNotes() async throws -> [AppleNoteRaw] {
        try reader.fetchAllNotes()
            .filter(isVisible)
    }

    public func searchNotes(query: String, limit: Int, folder: String? = nil) async throws -> [AppleNoteRaw] {
        NoteSearch.rank(notes: try await fetchAllNotes(), query: query, limit: limit, folder: folder, scope: scope)
    }

    public func fetchNote(id: String) async throws -> AppleNoteRaw? {
        guard let note = try reader.fetchNote(id: id), isVisible(note) else { return nil }
        return note
    }

    public func renderMarkdownBody(for body: AppleNoteBody) async throws -> String {
        try reader.renderMarkdownBody(for: body)
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

    /// Relocate a folder. Apple's scripting `move` deletes folders rather than re-parenting
    /// them (ADR 0002), so a move is a recreate-and-move-notes plan: recreate the source subtree
    /// under the new parent, move every note in (note ids survive the move), then delete the
    /// emptied source. Not atomic — a mid-way failure throws before the source is deleted, so
    /// notes are never lost.
    public func moveFolder(path: String, toParent parentPath: String?) async throws {
        let account = try resolveAccountName()
        let source = scope.resolvedFolder(path, defaultAccount: account).accountRelativePath
        let destParent = parentPath.map { scope.resolvedFolder($0, defaultAccount: account).accountRelativePath }

        let subtree = try gatherSubtree(source: source, account: account)
        let plan: FolderMovePlanner.Plan
        do {
            plan = try FolderMovePlanner.plan(
                source: source, destParent: destParent,
                subtreeFolders: subtree.folders, notes: subtree.notes
            )
        } catch let error as FolderMovePlanner.PlanError {
            throw Self.mapPlanError(error, path: path)
        }

        for create in plan.creates {
            try await writer.createFolder(name: create.name, parentName: create.parent)
        }
        for move in plan.moves {
            try await writer.moveNote(id: move.id, toFolder: move.toFolder)
        }
        try await writer.deleteFolder(path: plan.delete)
    }

    // MARK: - Folder-move helpers

    private func resolveAccountName() throws -> String {
        if let account = scope.selectedAccount, !account.isEmpty { return account }
        return try reader.fetchDefaultAccountName() ?? ""
    }

    /// Gather the source folder + its descendants and the notes living anywhere within, all as
    /// account-relative paths. Locked notes are included: they must move with the folder, never
    /// be deleted with it.
    private func gatherSubtree(
        source: String, account: String
    ) throws -> (folders: [String], notes: [FolderMovePlanner.NoteRef]) {
        let inSubtree: (String) -> Bool = { $0 == source || $0.hasPrefix(source + "/") }
        let folders = try reader.fetchFolders()
            .map { FolderPath($0.path).relative(to: account) }
            .filter(inSubtree)
        let notes = try reader.fetchAllNoteMetadata().compactMap { meta -> FolderMovePlanner.NoteRef? in
            let folder = FolderPath(meta.folderPath).relative(to: account)
            guard inSubtree(folder) else { return nil }
            return FolderMovePlanner.NoteRef(id: meta.id, folder: folder)
        }
        return (folders, notes)
    }

    private static func mapPlanError(_ error: FolderMovePlanner.PlanError, path: String) -> NotesError {
        switch error {
        case .sourceNotFound:
            return .folderNotFound(path: path)
        case .alreadyAtDestination:
            return .commandFailed(message: "Folder is already in that location: \(path)")
        case .intoOwnSubtree:
            return .commandFailed(message: "Cannot move a folder into its own subtree: \(path)")
        }
    }

    private func isVisible(_ note: AppleNoteMetadata) -> Bool {
        scope.isInSelectedAccount(note.folderPath) && !note.isLocked
    }

    private func isVisible(_ note: AppleNoteRaw) -> Bool {
        scope.isInSelectedAccount(note.folderPath) && !note.isLocked
    }
}
