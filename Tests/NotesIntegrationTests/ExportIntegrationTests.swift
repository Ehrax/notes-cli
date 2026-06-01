import Testing
import Foundation
import NotesTestSupport
@testable import NotesCore

@Suite("Export Integration")
struct ExportIntegrationTests {
    @Test func exportsMarkdownWithFrontmatter() async throws {
        let db = try makeRealDatabase()
        let note = makeSampleNote(
            id: "n1", title: "MD Test",
            bodyPlaintext: "Heading Paragraph",
            folderPath: "iCloud/Notes"
        )
        try await db.insertNote(note)

        let tag = try await db.insertTag(Tag(name: "test"))
        try await db.addTag(noteID: "n1", tagID: tag.id!)

        let tempDir = try makeTempDirectory(prefix: "export-md")
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(db: db, resolver: MockAttachmentResolver())
        let result = try await service.export(
            format: .md, outputDir: tempDir.path
        )

        #expect(result.exported == 1)
        #expect(result.folders == 1)

        let notesDir = tempDir.appendingPathComponent("iCloud/Notes")
        let files = try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
        let mdFile = files.first { $0.hasSuffix("-md-test.md") }
        #expect(mdFile != nil)
        let content = try String(
            contentsOf: notesDir.appendingPathComponent(mdFile!), encoding: .utf8
        )
        #expect(content.hasPrefix("---\n"))
        #expect(content.contains("title: \"MD Test\""))
        #expect(content.contains("tags: [\"test\"]"))
        #expect(content.contains("Heading Paragraph"))
    }
}
