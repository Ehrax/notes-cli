import Testing
import ArgumentParser
@testable import NotesCLI
@testable import NotesCore

@Suite("ExportCommand")
struct ExportCommandTests {
    @Test func parsesDefaults() throws {
        let command = try ExportCommand.parse([])
        #expect(command.type == .md)
        #expect(command.output == "./notes-cli-export/")
        #expect(command.folder == nil)
    }

    @Test func parsesAllOptions() throws {
        let command = try ExportCommand.parse([
            "--type", "json",
            "--output", "/tmp/export",
            "--folder", "notes-cli/projects",
        ])
        #expect(command.type == .json)
        #expect(command.output == "/tmp/export")
        #expect(command.folder == "notes-cli/projects")
    }

    @Test func parsesJSONFormat() throws {
        let command = try ExportCommand.parse(["--type", "json"])
        #expect(command.type == .json)
    }

    @Test func rejectsInvalidFormat() {
        #expect(throws: (any Error).self) {
            try ExportCommand.parse(["--type", "csv"])
        }
    }

    @Test func rejectsHTMLFormat() {
        #expect(throws: (any Error).self) {
            try ExportCommand.parse(["--type", "html"])
        }
    }
}
