import Foundation
import Testing

@testable import NotesCore

@Suite("Note Model Tests")
struct NoteTests {
    @Test("Note encodes only live Apple Notes fields")
    func noteEncodingUsesLiveFieldsOnly() throws {
        let note = Note(
            id: "enc-1",
            title: "Encode Me",
            bodyPlaintext: "Body",
            folderPath: "/Tests",
            isLocked: true
        )

        let data = try JSONEncoder().encode(note)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["id"] as? String == "enc-1")
        #expect(object["title"] as? String == "Encode Me")
        #expect(object["bodyPlaintext"] as? String == "Body")
        #expect(object["checksum"] == nil)
        #expect(object["syncedAt"] == nil)
    }

    @Test("Note maps raw Apple Notes data without sync metadata")
    func noteMapsRawAppleNotesData() {
        let raw = AppleNoteRaw(
            id: "raw-1",
            name: "Raw",
            bodyProtobuf: Data("body".utf8),
            bodyPlaintext: "Body",
            folderName: "Notes",
            folderPath: "iCloud/Notes",
            creationDate: Date(timeIntervalSince1970: 1),
            modificationDate: Date(timeIntervalSince1970: 2),
            isLocked: false
        )

        let note = Note(from: raw)

        #expect(note.id == "raw-1")
        #expect(note.title == "Raw")
        #expect(note.folderPath == "iCloud/Notes")
        #expect(note.bodyPlaintext == "Body")
    }

    @Test("Notes scope resolves nil folder to configured root folder")
    func notesScopeResolvesNilFolderToRootFolder() {
        let scope = Config.NotesScope(selectedAccount: "iCloud", rootFolder: "notes-cli")

        #expect(scope.resolvedFolderPath(nil) == "iCloud/notes-cli")
        #expect(scope.resolvedFolder(nil).account == "iCloud")
        #expect(scope.resolvedFolder(nil).accountRelativePath == "notes-cli")
    }

    @Test("Notes scope strips a supplied default account when no account is configured")
    func notesScopeUsesDefaultAccountForResolvedFolder() {
        let scope = Config.NotesScope()

        #expect(scope.resolvedFolder("iCloud/Projects", defaultAccount: "iCloud").account == "iCloud")
        #expect(scope.resolvedFolder("iCloud/Projects", defaultAccount: "iCloud").accountRelativePath == "Projects")
        #expect(scope.resolvedFolder("Projects", defaultAccount: "iCloud").accountRelativePath == "Projects")
    }
}
