import Foundation
import Testing
@testable import NotesCore
import NotesTestSupport

@Suite("AppleScriptConstants Tests")
struct AppleNotesServiceTests {

    // MARK: - AppleScript String Generation

    @Test("Create note script inserts sanitized parameters in order")
    func createNoteScriptGeneration() {
        let folder = "My \"Folder\""
        let title = "Test \"Title\""
        let body = "<p>Hello \"World\"</p>"

        let script = AppleScriptConstants.createNote(accountName: "iCloud")
            .replacingFirstOccurrence(of: "%@", with: folder.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: title.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: body.sanitizedForAppleScript)

        #expect(script.contains("\" & quote & \""))
        #expect(script.contains("iCloud"))
        // All three placeholders replaced
        #expect(script.contains("My "))
        #expect(script.contains("Test "))
        #expect(script.contains("Hello "))
        // No raw unescaped placeholder remains
        #expect(!script.contains("%@"))
    }

    @Test("Delete note script inserts sanitized ID")
    func deleteNoteScriptGeneration() {
        let noteID = "x-coredata://ABC-123"
        let script = AppleScriptConstants.deleteNote
            .replacingOccurrences(of: "%@", with: noteID.sanitizedForAppleScript)

        #expect(script.contains(noteID))
        #expect(!script.contains("%@"))
    }

    @Test("Move note script uses sequential placeholder replacement")
    func moveNoteScriptGeneration() {
        let noteID = "x-coredata://NOTE-1"
        let folderName = "iCloud/Projects/Archive"

        let script = AppleScriptConstants.moveNote(accountName: "iCloud")
            .replacingFirstOccurrence(of: "%@", with: folderName.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: noteID.sanitizedForAppleScript)

        #expect(script.contains(noteID))
        #expect(script.contains(folderName))
        #expect(script.contains("notes-cli_folder_for_path"))
        #expect(!script.contains("%@"))
    }

    @Test("Update note script with both title and body")
    func updateNoteScriptGeneration() {
        let noteID = "x-coredata://NOTE-2"
        let title = "Updated"
        let body = "<p>New body</p>"

        let script = AppleScriptConstants.updateNote
            .replacingFirstOccurrence(of: "%@", with: noteID.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: title.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: body.sanitizedForAppleScript)

        #expect(script.contains(noteID))
        #expect(script.contains(title))
        #expect(script.contains(body))
        #expect(!script.contains("%@"))
    }

    // MARK: - Sanitization

    @Test("String sanitization escapes quotes via AppleScript concatenation")
    func stringSanitization() {
        let input = #"Hello "World""#
        let sanitized = input.sanitizedForAppleScript
        #expect(sanitized == #"Hello " & quote & "World" & quote & ""#)
    }

    @Test("String sanitization handles empty string")
    func stringSanitizationEmpty() {
        #expect("".sanitizedForAppleScript == "")
    }

    // MARK: - Folder Script Generation

    @Test("Create folder script inserts sanitized name")
    func createFolderScriptGeneration() {
        let name = "New \"Folder\""
        let script = AppleScriptConstants.createFolder(accountName: "iCloud")
            .replacingOccurrences(of: "%@", with: name.sanitizedForAppleScript)

        #expect(script.contains("\" & quote & \""))
        #expect(script.contains("tell targetAccount"))
        #expect(!script.contains("%@"))
    }

    @Test("Create subfolder script uses parent path resolution")
    func createSubfolderScriptGeneration() {
        let parent = "iCloud/Work/Projects"
        let name = "Child"

        let script = AppleScriptConstants.createSubfolder(accountName: "iCloud")
            .replacingFirstOccurrence(of: "%@", with: parent.sanitizedForAppleScript)
            .replacingFirstOccurrence(of: "%@", with: name.sanitizedForAppleScript)

        #expect(script.contains("notes-cli_folder_for_path"))
        #expect(script.contains("Work/Projects"))
        #expect(script.contains("Child"))
        #expect(!script.contains("%@"))
    }

    @Test("Folder path helper splits path components using slash delimiters")
    func folderPathHelperUsesSlashDelimiters() {
        let script = AppleScriptConstants.createSubfolder(accountName: "iCloud")
        #expect(script.contains("set AppleScript's text item delimiters to \"/\""))
        #expect(script.contains("set beginning of pathParts to name of currentContainer"))
        #expect(script.contains("name of every account"))
        #expect(script.contains("Notes account not found"))
        #expect(script.contains("Folder path belongs to a different account"))
        #expect(!script.contains("exists account whose name is"))
        #expect(script.contains("if relativePath is \"\" then"))
        #expect(script.contains("return targetAccount"))
    }

    // MARK: - Mock Notes Service

    @Test("MockNotesService tracks method calls")
    func mockServiceTracksCalls() async throws {
        let mock = MockNotesService()
        mock.accountNames = ["iCloud"]
        mock.defaultAccountName = "iCloud"
        mock.notes = [
            AppleNoteRaw(
                id: "test-1",
                name: "Test Note",
                bodyProtobuf: Data(),
                bodyPlaintext: "Body",
                folderName: "Notes",
                folderPath: "Work/Notes",
                creationDate: Date(),
                modificationDate: Date(),
                isLocked: false
            ),
        ]

        let notes = try await mock.fetchAllNotes()
        let accounts = try await mock.fetchAccountNames()
        let defaultAccount = try await mock.fetchDefaultAccountName()
        #expect(accounts == ["iCloud"])
        #expect(defaultAccount == "iCloud")
        #expect(mock.fetchAllNotesCalled)
        #expect(mock.fetchAccountNamesCalled)
        #expect(mock.fetchDefaultAccountNameCalled)
        #expect(notes.count == 1)

        let note = try await mock.fetchNote(id: "test-1")
        #expect(mock.fetchNoteCalled)
        #expect(note?.name == "Test Note")
        #expect(note?.folderPath == "Work/Notes")
    }

    @Test("MockNotesService throws configured errors")
    func mockServiceThrowsErrors() async {
        let mock = MockNotesService()
        mock.errorToThrow = NotesError.appleNotesUnavailable

        do {
            _ = try await mock.fetchAllNotes()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is NotesError)
        }
    }

    // MARK: - replacingFirstOccurrence helper

    @Test("replacingFirstOccurrence replaces only first match")
    func replacingFirstOccurrence() {
        let input = "%@ and %@ and %@"
        let result = input
            .replacingFirstOccurrence(of: "%@", with: "first")
            .replacingFirstOccurrence(of: "%@", with: "second")
            .replacingFirstOccurrence(of: "%@", with: "third")
        #expect(result == "first and second and third")
    }
}
