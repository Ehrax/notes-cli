import Testing
import Foundation
import NotesTestSupport
@testable import NotesCore

@Suite("ExportService")
struct ExportServiceTests {
    @Test func exportsMarkdownNotes() async throws {
        let mock = MockNotesService()
        mock.notes = [makeSampleAppleNote(id: "n1", name: "Test", folder: "iCloud/Notes")]

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
        let result = try await service.export(
            format: .md, outputDir: tempDir.path
        )

        #expect(result.exported == 1)
        #expect(result.skipped == 0)

        // Find the exported file (filename has date prefix)
        let notesDir = tempDir.appendingPathComponent("iCloud/Notes")
        let files = try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
        let mdFile = files.first { $0.hasSuffix("-test.md") }
        #expect(mdFile != nil)
        let content = try String(
            contentsOf: notesDir.appendingPathComponent(mdFile!), encoding: .utf8
        )
        #expect(content.contains("Hello"))
    }

    @Test func exportsJSONNotes() async throws {
        let mock = MockNotesService()
        mock.notes = [makeSampleAppleNote(id: "n1", name: "Test", bodyPlaintext: "Hello", folder: "iCloud/Notes")]

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
        let result = try await service.export(
            format: .json, outputDir: tempDir.path
        )

        #expect(result.exported == 1)

        let notesDir = tempDir.appendingPathComponent("iCloud/Notes")
        let files = try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
        let jsonFile = try #require(files.first { $0.hasSuffix("-test.json") })
        let data = try Data(contentsOf: notesDir.appendingPathComponent(jsonFile))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["title"] as? String == "Test")
        #expect(object?["body"] as? String == "Hello")
        #expect(object?["folderPath"] as? String == "iCloud/Notes")
    }

    @Test func preservesFolderStructure() async throws {
        let mock = MockNotesService()
        mock.notes = [
            makeSampleAppleNote(id: "n1", name: "A", folder: "iCloud/notes-cli/projects"),
            makeSampleAppleNote(id: "n2", name: "B", folder: "iCloud/notes-cli/journal"),
        ]

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
        let result = try await service.export(
            format: .md, outputDir: tempDir.path
        )

        #expect(result.exported == 2)
        #expect(result.folders == 2)

        let projectsDir = tempDir.appendingPathComponent("iCloud/notes-cli/projects")
        let journalDir = tempDir.appendingPathComponent("iCloud/notes-cli/journal")
        let projFiles = try FileManager.default.contentsOfDirectory(atPath: projectsDir.path)
        let jourFiles = try FileManager.default.contentsOfDirectory(atPath: journalDir.path)
        #expect(projFiles.contains { $0.hasSuffix("-a.md") })
        #expect(jourFiles.contains { $0.hasSuffix("-b.md") })
    }

    @Test func deduplicatesFilenames() async throws {
        let mock = MockNotesService()
        mock.notes = [
            makeSampleAppleNote(id: "n1", name: "Same", folder: "Notes"),
            makeSampleAppleNote(id: "n2", name: "Same", folder: "Notes"),
        ]

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
        let result = try await service.export(
            format: .md, outputDir: tempDir.path
        )

        #expect(result.exported == 2)
        let notesDir = tempDir.appendingPathComponent("Notes")
        let files = try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
        let sameFiles = files.filter { $0.contains("same") }
        #expect(sameFiles.count == 2)
        #expect(sameFiles.contains { $0.hasSuffix("-same.md") })
        #expect(sameFiles.contains { $0.hasSuffix("-same-2.md") })
    }

    @Test func keepsSameNamedAttachmentsSeparateInOneFolder() async throws {
        let mock = MockNotesService()
        mock.notes = [
            makeSampleAppleNote(
                id: "n1", name: "First",
                bodyPlaintext: "One\n![[attachment:attachment-one:public.png]]",
                folder: "Notes"
            ),
            makeSampleAppleNote(
                id: "n2", name: "Second",
                bodyPlaintext: "Two\n![[attachment:attachment-two:public.png]]",
                folder: "Notes"
            ),
        ]

        let mediaRoot = try makeTempDirectory(prefix: "notes-cli-media")
        let outputRoot = try makeTempDirectory()
        defer {
            removeTempDirectory(mediaRoot)
            removeTempDirectory(outputRoot)
        }

        let firstSource = mediaRoot.appendingPathComponent("first/image.png")
        let secondSource = mediaRoot.appendingPathComponent("second/image.png")
        try FileManager.default.createDirectory(
            at: firstSource.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondSource.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        mock.attachmentsByNoteID = [
            "n1": [
                NoteAttachment(
                    id: "attachment-one", noteID: "n1", filename: "image.png",
                    typeUTI: "public.png", relativePath: "first/image.png"
                ),
            ],
            "n2": [
                NoteAttachment(
                    id: "attachment-two", noteID: "n2", filename: "image.png",
                    typeUTI: "public.png", relativePath: "second/image.png"
                ),
            ],
        ]

        let service = ExportService(notes: mock, appleNotesRootURL: mediaRoot)
        let result = try await service.export(format: .md, outputDir: outputRoot.path)

        #expect(result.exported == 2)
        let notesDir = outputRoot.appendingPathComponent("Notes")
        let assetsDir = notesDir.appendingPathComponent("assets")
        let assets = try FileManager.default.contentsOfDirectory(atPath: assetsDir.path).sorted()
        #expect(assets == ["attachment-one-image.png", "attachment-two-image.png"])

        let firstMarkdown = try String(
            contentsOf: notesDir.appendingPathComponent(
                try #require(try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
                    .first { $0.hasSuffix("-first.md") })
            ),
            encoding: .utf8
        )
        let secondMarkdown = try String(
            contentsOf: notesDir.appendingPathComponent(
                try #require(try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
                    .first { $0.hasSuffix("-second.md") })
            ),
            encoding: .utf8
        )
        #expect(firstMarkdown.contains("![[assets/attachment-one-image.png]]"))
        #expect(secondMarkdown.contains("![[assets/attachment-two-image.png]]"))
        #expect(try Data(contentsOf: assetsDir.appendingPathComponent("attachment-one-image.png")) == Data("first".utf8))
        #expect(try Data(contentsOf: assetsDir.appendingPathComponent("attachment-two-image.png")) == Data("second".utf8))
    }

    @Test func filtersByFolder() async throws {
        let mock = MockNotesService()
        mock.notes = [
            makeSampleAppleNote(id: "n1", name: "A", folder: "iCloud/notes-cli/projects"),
            makeSampleAppleNote(id: "n2", name: "B", folder: "iCloud/notes-cli/journal"),
        ]

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
        let result = try await service.export(
            format: .md, outputDir: tempDir.path,
            folder: "notes-cli/projects",
            scope: .init(selectedAccount: "iCloud")
        )

        #expect(result.exported == 1)
    }

    @Test func returnsZeroForNoMatches() async throws {
        let mock = MockNotesService()
        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
        let result = try await service.export(
            format: .md, outputDir: tempDir.path
        )

        #expect(result.exported == 0)
        #expect(result.skipped == 0)
    }

    @Test func createsOutputDirectoryAndLogForNoMatches() async throws {
        let mock = MockNotesService()
        let parent = try makeTempDirectory()
        defer { removeTempDirectory(parent) }
        let output = parent.appendingPathComponent("new-export")

        let service = ExportService(notes: mock)
        let result = try await service.export(format: .md, outputDir: output.path)

        #expect(result.exported == 0)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("LOG.md").path))
    }

    @Test func markdownFrontmatterFormatsCorrectly() {
        let note = makeSampleNote(
            id: "n1", title: "My Note",
            folderPath: "Notes"
        )
        let result = ExportService.markdownWithFrontmatter(
            note: note, body: "Hello"
        )
        #expect(result.hasPrefix("---\n"))
        #expect(result.contains("title: \"My Note\""))
        #expect(result.contains("created:"))
        #expect(result.contains("modified:"))
        #expect(result.contains("apple_note_id: \"n1\""))
        #expect(result.contains("apple_folder: \"Notes\""))
        #expect(!result.contains("tags:"))
        #expect(result.contains("---\nHello"))
    }

    @Test func writesLogForPartialAndFailedNotes() async throws {
        let mock = MockNotesService()
        mock.notes = [
            makeSampleAppleNote(
                id: "partial-id", name: "Partial",
                bodyPlaintext: "", folder: "iCloud/Notes",
                snippet: "Content still exists"
            ),
            makeSampleAppleNote(
                id: "complete-id", name: "Complete",
                bodyPlaintext: "Body", folder: "iCloud/Notes"
            ),
        ]

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
        let result = try await service.export(format: .md, outputDir: tempDir.path)

        #expect(result.exported == 2)
        #expect(result.partial == 1)

        let log = try String(
            contentsOf: tempDir.appendingPathComponent("LOG.md"),
            encoding: .utf8
        )
        #expect(log.contains("Exported: 2"))
        #expect(log.contains("Partial: 1"))
        #expect(log.contains("partial-id"))
        #expect(log.contains("Partial"))
        #expect(log.contains("Rendered body is empty"))
        #expect(!log.contains("complete-id"))
    }

    @Test func markdownFrontmatterEscapesQuotesInTitle() {
        let note = makeSampleNote(
            id: "n1", title: "He said \"hello\"",
            folderPath: "Notes"
        )
        let result = ExportService.markdownWithFrontmatter(
            note: note, body: "Hi"
        )
        #expect(result.contains("title: \"He said \\\"hello\\\"\""))
    }

    @Test func markdownFrontmatterNeverEmitsTags() {
        let note = makeSampleNote(
            id: "n1", title: "T", folderPath: "Notes"
        )
        let result = ExportService.markdownWithFrontmatter(
            note: note, body: "Body"
        )
        #expect(!result.contains("tags:"))
    }
}
