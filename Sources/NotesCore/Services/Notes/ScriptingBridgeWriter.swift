import Foundation
import NotesCoreObjC

/// The single write path to Apple Notes, via ScriptingBridge (ADR 0002).
///
/// Resolves a folder argument against the configured scope, then delegates the actual
/// Apple Events to the `NotesSB*` ObjC functions (pure Swift can't drive the generated SB
/// element classes). Notes are addressed by the `x-coredata://…/ICNote/p<pk>` id the reader emits.
@MainActor
public final class ScriptingBridgeWriter: Sendable {
    private let scope: Config.NotesScope

    public init(scope: Config.NotesScope) {
        self.scope = scope
    }

    // MARK: - Write operations

    public func createNote(title: String, bodyHTML: String, folderName: String) throws -> String {
        let target = resolved(folderName)
        var error: NSError?
        let body = NoteHTML.composeBody(title: title, contentHTML: bodyHTML)
        guard let id = NotesSBCreateNote(target.account, target.path, body, &error) else {
            throw Self.mapError(error)
        }
        return id
    }

    public func updateNote(id: String, title: String?, bodyHTML: String?) throws {
        var error: NSError?
        let ok: Bool
        if let bodyHTML {
            // Replacing the body: bake the title into the first line and let Apple derive the
            // name, so a title is never rendered twice.
            ok = NotesSBUpdateNote(id, nil, NoteHTML.composeBody(title: title, contentHTML: bodyHTML), &error)
        } else {
            // Title-only edit: update the metadata name in place (no body to rewrite).
            ok = NotesSBUpdateNote(id, title, nil, &error)
        }
        if !ok {
            throw Self.mapError(error, noteID: id)
        }
    }

    public func deleteNote(id: String) throws {
        var error: NSError?
        if !NotesSBDeleteNote(id, &error) {
            throw Self.mapError(error, noteID: id)
        }
    }

    public func moveNote(id: String, toFolder folderName: String) throws {
        let target = resolved(folderName)
        var error: NSError?
        if !NotesSBMoveNote(id, target.account, target.path, &error) {
            throw Self.mapError(error, noteID: id)
        }
    }

    public func createFolder(name: String, parentName: String?) throws {
        let parent = parentName.map(resolved) ?? (account: scope.selectedAccount, path: "")
        var error: NSError?
        if !NotesSBCreateFolder(parent.account, parent.path.isEmpty ? nil : parent.path, name, &error) {
            throw Self.mapError(error)
        }
    }

    public func renameFolder(path: String, newName: String) throws {
        let target = resolved(path)
        var error: NSError?
        if !NotesSBRenameFolder(target.account, target.path, newName, &error) {
            throw Self.mapError(error)
        }
    }

    public func deleteFolder(path: String) throws {
        let target = resolved(path)
        var error: NSError?
        if !NotesSBDeleteFolder(target.account, target.path, &error) {
            throw Self.mapError(error)
        }
    }

    // Folder moves are not a single ScriptingBridge call: Apple's `move` command deletes folders
    // rather than re-parenting them (ADR 0002). DirectNotesService composes a move from
    // createFolder + per-note moveNote + deleteFolder, which the writer already exposes.

    // MARK: - Availability

    public func isAvailable() throws -> Bool {
        NotesSBDefaultAccountName() != nil
    }

    // MARK: - Helpers

    /// Resolve a user folder argument into (account name, account-relative "/"-path).
    private func resolved(_ folderName: String?) -> (account: String?, path: String) {
        let full = scope.resolvedFolderPath(folderName)
        guard let account = scope.selectedAccount, !account.isEmpty else {
            return (nil, full)
        }
        if full == account { return (account, "") }
        if full.hasPrefix(account + "/") { return (account, String(full.dropFirst(account.count + 1))) }
        return (account, full)
    }

    private static func mapError(_ error: NSError?, noteID: String? = nil) -> NotesError {
        let message = error?.localizedDescription ?? "unknown error"
        if message.contains("note not found"), let noteID {
            return .noteNotFound(id: noteID)
        }
        if message.contains("folder not found") || message.contains("account not found") {
            return .folderNotFound(path: message)
        }
        return .scriptingBridgeError(message: "Notes write failed: \(message)", number: nil)
    }
}
