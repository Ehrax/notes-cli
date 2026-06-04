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
            bodyProtobuf: Data("**Body**".utf8),
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
}
