import Foundation
import Testing

@testable import NotesCore

@Suite("Note Model Tests")
struct NoteTests {

    @Test("Checksum is computed from bodyProtobuf")
    func checksumComputed() {
        let bodyData = Data("**Hello World**".utf8)
        let note = Note(
            id: "test-1",
            title: "Test",
            bodyProtobuf: bodyData,
            bodyPlaintext: "Hello World",
            folderPath: "/Notes"
        )

        let expected = Note.computeChecksum(bodyData)
        #expect(note.checksum == expected)
        #expect(!note.checksum.isEmpty)
    }

    @Test("Checksum changes when bodyProtobuf changes")
    func checksumChangesWithContent() {
        let checksum1 = Note.computeChecksum(Data("Hello".utf8))
        let checksum2 = Note.computeChecksum(Data("World".utf8))
        #expect(checksum1 != checksum2)
    }

    @Test("Checksum is deterministic")
    func checksumDeterministic() {
        let body = Data("**Consistent**".utf8)
        let a = Note.computeChecksum(body)
        let b = Note.computeChecksum(body)
        #expect(a == b)
    }

    @Test("Note encoding and decoding")
    func noteEncodingDecoding() throws {
        let note = Note(
            id: "enc-1",
            title: "Encode Me",
            bodyProtobuf: Data("**Body**".utf8),
            bodyPlaintext: "Body",
            folderPath: "/Tests",
            isLocked: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(note)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Note.self, from: data)

        #expect(decoded.id == note.id)
        #expect(decoded.title == note.title)
        #expect(decoded.bodyProtobuf == note.bodyProtobuf)
        #expect(decoded.bodyPlaintext == note.bodyPlaintext)
        #expect(decoded.folderPath == note.folderPath)
        #expect(decoded.isLocked == note.isLocked)
        #expect(decoded.checksum == note.checksum)
    }

    @Test("Note default values")
    func noteDefaults() {
        let note = Note(
            id: "def-1",
            title: "Defaults",
            bodyProtobuf: Data("Test".utf8),
            bodyPlaintext: "Test",
            folderPath: "/Notes"
        )

        #expect(note.isLocked == false)
        #expect(!note.checksum.isEmpty)
    }

    @Test("Custom checksum override")
    func customChecksumOverride() {
        let note = Note(
            id: "custom-1",
            title: "Custom",
            bodyProtobuf: Data("Body".utf8),
            bodyPlaintext: "Body",
            folderPath: "/Notes",
            checksum: "custom-hash"
        )

        #expect(note.checksum == "custom-hash")
    }
}
