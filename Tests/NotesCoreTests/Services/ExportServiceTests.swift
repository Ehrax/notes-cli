import Testing
import Foundation
import NotesTestSupport
@testable import NotesCore

@Suite("ExportService")
struct ExportServiceTests {
    @Test func exportsMarkdownNotes() async throws {
        let mockDB = MockDatabaseService()
        let note = makeSampleNote(
            id: "n1", title: "Test",
            folderPath: "iCloud/Notes"
        )
        mockDB.notes["n1"] = note

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: mockDB, resolver: MockAttachmentResolver())
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

    @Test func preservesFolderStructure() async throws {
        let mockDB = MockDatabaseService()
        mockDB.notes["n1"] = makeSampleNote(
            id: "n1", title: "A",
            folderPath: "iCloud/notes-cli/projects"
        )
        mockDB.notes["n2"] = makeSampleNote(
            id: "n2", title: "B",
            folderPath: "iCloud/notes-cli/journal"
        )

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: mockDB, resolver: MockAttachmentResolver())
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
        let mockDB = MockDatabaseService()
        mockDB.notes["n1"] = makeSampleNote(
            id: "n1", title: "Same",
            folderPath: "Notes"
        )
        mockDB.notes["n2"] = makeSampleNote(
            id: "n2", title: "Same",
            folderPath: "Notes"
        )

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: mockDB, resolver: MockAttachmentResolver())
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

    @Test func filtersByAccount() async throws {
        let mockDB = MockDatabaseService()
        mockDB.notes["n1"] = makeSampleNote(
            id: "n1", title: "A", folderPath: "iCloud/Notes"
        )
        mockDB.notes["n2"] = makeSampleNote(
            id: "n2", title: "B", folderPath: "Gmail/Notes"
        )

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: mockDB, resolver: MockAttachmentResolver())
        let result = try await service.export(
            format: .md, outputDir: tempDir.path,
            account: "iCloud"
        )

        #expect(result.exported == 1)
    }

    @Test func filtersByFolder() async throws {
        let mockDB = MockDatabaseService()
        mockDB.notes["n1"] = makeSampleNote(
            id: "n1", title: "A",
            folderPath: "iCloud/notes-cli/projects"
        )
        mockDB.notes["n2"] = makeSampleNote(
            id: "n2", title: "B",
            folderPath: "iCloud/notes-cli/journal"
        )

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: mockDB, resolver: MockAttachmentResolver())
        let result = try await service.export(
            format: .md, outputDir: tempDir.path,
            folder: "projects"
        )

        #expect(result.exported == 1)
    }

    @Test func filtersByTag() async throws {
        let mockDB = MockDatabaseService()
        mockDB.notes["n1"] = makeSampleNote(id: "n1", title: "A")
        mockDB.notes["n2"] = makeSampleNote(id: "n2", title: "B")
        let tag = try await mockDB.insertTag(Tag(name: "active"))
        try await mockDB.addTag(noteID: "n1", tagID: tag.id!)

        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: mockDB, resolver: MockAttachmentResolver())
        let result = try await service.export(
            format: .md, outputDir: tempDir.path,
            tag: "active"
        )

        #expect(result.exported == 1)
    }

    @Test func returnsZeroForNoMatches() async throws {
        let mockDB = MockDatabaseService()
        let tempDir = try makeTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: mockDB, resolver: MockAttachmentResolver())
        let result = try await service.export(
            format: .md, outputDir: tempDir.path
        )

        #expect(result.exported == 0)
        #expect(result.skipped == 0)
    }

    @Test func markdownFrontmatterFormatsCorrectly() {
        let note = makeSampleNote(
            id: "n1", title: "My Note",
            folderPath: "Notes"
        )
        let result = ExportService.markdownWithFrontmatter(
            note: note, tags: ["tag1", "tag2"], body: "Hello"
        )
        #expect(result.hasPrefix("---\n"))
        #expect(result.contains("title: \"My Note\""))
        #expect(result.contains("created:"))
        #expect(result.contains("modified:"))
        #expect(result.contains("tags: [\"tag1\", \"tag2\"]"))
        #expect(result.contains("---\nHello"))
    }

    @Test func markdownFrontmatterEscapesQuotesInTitle() {
        let note = makeSampleNote(
            id: "n1", title: "He said \"hello\"",
            folderPath: "Notes"
        )
        let result = ExportService.markdownWithFrontmatter(
            note: note, tags: [], body: "Hi"
        )
        #expect(result.contains("title: \"He said \\\"hello\\\"\""))
    }

    @Test func markdownFrontmatterOmitsTagsWhenEmpty() {
        let note = makeSampleNote(
            id: "n1", title: "T", folderPath: "Notes"
        )
        let result = ExportService.markdownWithFrontmatter(
            note: note, tags: [], body: "Body"
        )
        #expect(!result.contains("tags:"))
    }
}
