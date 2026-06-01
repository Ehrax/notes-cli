import Foundation

/// Write-only Apple Notes service using NSAppleScript via AppleScriptRunner.
/// Handles create, update, delete, and move operations that must go through
/// Notes.app to maintain Core Data and CloudKit integrity.
@MainActor
public final class AppleScriptWriter: Sendable {
    private let runner: AppleScriptRunner
    private let scope: Config.NotesScope

    public init(runner: AppleScriptRunner, scope: Config.NotesScope) {
        self.runner = runner
        self.scope = scope
    }

    // MARK: - Write Operations

    /// Create a new note in the specified folder. Returns the new note's ID.
    public func createNote(title: String, bodyHTML: String, folderName: String) throws -> String {
        let resolvedFolderName = scope.resolvedFolderPath(folderName)
        let script = AppleScriptConstants.createNote(accountName: scope.selectedAccount)
            .replacingFirstOccurrence(of: "%@", with: resolvedFolderName.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: title.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: bodyHTML.sanitizedForAppleScript)
        return try runner.executeString(script)
    }

    /// Update an existing note's title and/or body HTML.
    public func updateNote(id: String, title: String?, bodyHTML: String?) throws {
        if let title, let bodyHTML {
            let script = AppleScriptConstants.updateNote
                .replacingFirstOccurrence(of: "%@", with: id.sanitizedForAppleScript)
                .replacingFirstOccurrence(of: "%@", with: title.sanitizedForAppleScript)
                .replacingFirstOccurrence(of: "%@", with: bodyHTML.sanitizedForAppleScript)
            _ = try runner.execute(script)
        } else if let title {
            let script = AppleScriptConstants.updateNoteTitle
                .replacingFirstOccurrence(of: "%@", with: id.sanitizedForAppleScript)
                .replacingFirstOccurrence(of: "%@", with: title.sanitizedForAppleScript)
            _ = try runner.execute(script)
        } else if let bodyHTML {
            let script = AppleScriptConstants.updateNoteBody
                .replacingFirstOccurrence(of: "%@", with: id.sanitizedForAppleScript)
                .replacingFirstOccurrence(of: "%@", with: bodyHTML.sanitizedForAppleScript)
            _ = try runner.execute(script)
        }
    }

    /// Delete a note by ID.
    public func deleteNote(id: String) throws {
        let script = AppleScriptConstants.deleteNote
            .replacingOccurrences(of: "%@", with: id.sanitizedForAppleScript)
        _ = try runner.execute(script)
    }

    /// Move a note to a different folder.
    public func moveNote(id: String, toFolder folderName: String) throws {
        let resolvedFolderName = scope.resolvedFolderPath(folderName)
        let script = AppleScriptConstants.moveNote(accountName: scope.selectedAccount)
            .replacingFirstOccurrence(of: "%@", with: resolvedFolderName.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: id.sanitizedForAppleScript)
        _ = try runner.execute(script)
    }

    /// Create a folder, optionally nested under a parent folder.
    public func createFolder(name: String, parentName: String?) throws {
        if let parentName {
            let resolvedParentName = scope.resolvedFolderPath(parentName)
            let script = AppleScriptConstants.createSubfolder(accountName: scope.selectedAccount)
                .replacingFirstOccurrence(of: "%@", with: resolvedParentName.sanitizedForAppleScript)
                .replacingFirstOccurrence(of: "%@", with: name.sanitizedForAppleScript)
            _ = try runner.execute(script)
        } else {
            let script = AppleScriptConstants.createFolder(accountName: scope.selectedAccount)
                .replacingOccurrences(of: "%@", with: name.sanitizedForAppleScript)
            _ = try runner.execute(script)
        }
    }

    // MARK: - Availability

    /// Check if AppleScript can reach Apple Notes.
    public func isAvailable() throws -> Bool {
        let script = """
            tell application "Notes"
                return name of default account
            end tell
            """
        do {
            let result = try runner.executeString(script)
            return !result.isEmpty
        } catch let error as NotesError {
            if case .appleScriptError(_, let number) = error, number == -1743 {
                throw NotesError.appleScriptError(
                    message: "Automation permission denied. Grant access in System Settings > Privacy & Security > Automation.",
                    number: -1743
                )
            }
            return false
        } catch {
            return false
        }
    }
}
