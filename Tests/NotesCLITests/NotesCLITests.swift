import Testing
@testable import NotesCore

@Test func notesCLIVersion() {
    // NotesCLI CLI version matches NotesCore version
    #expect(NotesCore.version == "0.1.0")
}
