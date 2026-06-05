import Foundation
import Testing
@testable import NotesCLI
@testable import NotesCore

/// Captures stdout output from a synchronous block.
/// NOTE: Not safe for concurrent use - tests using this must be serialized.
private func captureStdout(_ block: () throws -> Void) rethrows -> String {
    fflush(stdout)
    let pipe = Pipe()
    let saved = dup(STDOUT_FILENO)
    setvbuf(stdout, nil, _IONBF, 0)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

    try block()

    fflush(stdout)
    pipe.fileHandleForWriting.closeFile()
    dup2(saved, STDOUT_FILENO)
    close(saved)

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// Run formatter tests serially to prevent stdout capture conflicts
@Suite("OutputFormatter Tests", .serialized)
struct OutputFormatterTests {
    private let sampleNotes: [Note] = [
        Note(
            id: "note-1",
            title: "First Note",
            bodyPlaintext: "Hello world",
            folderPath: "Notes",
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        Note(
            id: "note-2",
            title: "Second Note",
            bodyPlaintext: "Goodbye",
            folderPath: "Work",
            creationDate: Date(timeIntervalSince1970: 1_700_100_000),
            modificationDate: Date(timeIntervalSince1970: 1_700_100_000)
        ),
    ]

    private let sampleFolders: [Folder] = [
        Folder(id: "folder-1", name: "Notes", path: "Notes"),
        Folder(id: "folder-2", name: "Work", path: "Work"),
    ]

    // MARK: - JSON Tests

    @Test("JSON output for notes is valid JSON")
    func jsonNotesIsValidJSON() throws {
        let output = try captureStdout {
            try OutputFormatter.printNotes(sampleNotes, format: .json)
        }

        #expect(!output.isEmpty)
        let data = Data(output.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data)
        let array = try #require(parsed as? [[String: Any]])
        #expect(array.count == 2)
        #expect(array[0]["title"] as? String == "First Note")
        #expect(array[0]["checksum"] == nil)
        #expect(array[0]["syncedAt"] == nil)
        #expect(array[0]["bodyProtobuf"] == nil)
    }

    @Test("JSON output for folders is valid JSON")
    func jsonFoldersIsValidJSON() throws {
        let output = try captureStdout {
            try OutputFormatter.printFolders(sampleFolders, format: .json)
        }

        #expect(!output.isEmpty)
        let data = Data(output.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data)
        let array = try #require(parsed as? [[String: Any]])
        #expect(array.count == 2)
        #expect(array[0]["isProtected"] == nil)
        #expect(array[0]["sortOrder"] == nil)
    }

    // MARK: - Table Tests

    @Test("Table output has aligned columns with separator line")
    func tableOutputHasAlignedColumns() throws {
        let output = try captureStdout {
            try OutputFormatter.printNotes(sampleNotes, format: .table)
        }

        // Verify header row is present
        #expect(output.contains("ID"))
        #expect(output.contains("Title"))
        #expect(output.contains("Folder"))
        #expect(output.contains("Modified"))

        // Separator line should contain dashes
        #expect(output.contains("--"))

        // Verify data rows are present
        #expect(output.contains("First Note"))
        #expect(output.contains("Second Note"))

        // Verify alignment: header + separator + data rows
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count >= 3) // header + separator + at least one row

        // Header and separator should be the same length (aligned)
        if lines.count >= 2 {
            #expect(lines[0].count == lines[1].count)
        }
    }

    @Test("Table output for empty notes shows message")
    func tableEmptyNotes() throws {
        let output = try captureStdout {
            try OutputFormatter.printNotes([], format: .table)
        }

        #expect(output.contains("No notes found"))
    }

    // MARK: - Markdown Tests

    @Test("Markdown output has proper headers")
    func markdownOutputHasHeaders() throws {
        let output = try captureStdout {
            try OutputFormatter.printNotes(sampleNotes, format: .markdown)
        }

        #expect(output.contains("# Notes"))
        #expect(output.contains("## First Note"))
        #expect(output.contains("## Second Note"))
        #expect(output.contains("**ID:**"))
        #expect(output.contains("**Folder:**"))
    }

    @Test("Markdown folders uses table format")
    func markdownFoldersUsesTable() throws {
        let output = try captureStdout {
            try OutputFormatter.printFolders(sampleFolders, format: .markdown)
        }

        #expect(output.contains("# Folders"))
        #expect(output.contains("| Name |"))
        #expect(output.contains("| Notes |"))
        #expect(output.contains("| Work |"))
        #expect(!output.contains("Protected"))
    }

    @Test("Generic markdown output does not fall back to JSON")
    func genericMarkdownDoesNotFallBackToJSON() throws {
        struct StatusPayload: Encodable {
            let noteCount = 2
            let folderCount = 1
            let lastSync = "never"
        }

        let output = try captureStdout {
            try OutputFormatter.print(StatusPayload(), format: .markdown)
        }

        #expect(output.contains("# Output"))
        #expect(output.contains("**noteCount:** 2"))
        #expect(!output.contains("{\"folderCount\""))
    }

    @Test("Generic markdown output uses ISO8601 dates")
    func genericMarkdownUsesISO8601Dates() throws {
        struct DatePayload: Encodable {
            let generatedAt: Date
        }

        let output = try captureStdout {
            try OutputFormatter.print(
                DatePayload(generatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                format: .markdown
            )
        }

        #expect(output.contains("2023-11-14T22:13:20Z"))
    }
}
