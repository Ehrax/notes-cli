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
        #expect(command.live == false)
        #expect(command.account == nil)
        #expect(command.folder == nil)
        #expect(command.tag == nil)
    }

    @Test func parsesAllOptions() throws {
        let command = try ExportCommand.parse([
            "--type", "md",
            "--output", "/tmp/export",
            "--live",
            "--account", "iCloud",
            "--folder", "notes-cli/projects",
            "--tag", "active",
        ])
        #expect(command.type == .md)
        #expect(command.output == "/tmp/export")
        #expect(command.live == true)
        #expect(command.account == "iCloud")
        #expect(command.folder == "notes-cli/projects")
        #expect(command.tag == "active")
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

    @Test func rejectsJSONFormat() {
        #expect(throws: (any Error).self) {
            try ExportCommand.parse(["--type", "json"])
        }
    }
}
