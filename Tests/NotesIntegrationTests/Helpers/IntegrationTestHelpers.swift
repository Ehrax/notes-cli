import Foundation
import NotesCore
import NotesTestSupport

/// Creates a MockNotesService pre-populated with sample AppleNoteRaw data.
func makePopulatedMockNotes(count: Int) -> MockNotesService {
    let mock = MockNotesService()
    mock.notes = (0..<count).map { i in
        makeSampleAppleNote(
            id: "note-\(i)",
            name: "Note \(i)",
            bodyPlaintext: "Body of note \(i)",
            folder: i % 3 == 0 ? "Work" : (i % 3 == 1 ? "Personal" : "Notes")
        )
    }
    return mock
}
