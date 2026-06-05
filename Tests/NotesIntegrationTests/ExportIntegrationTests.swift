import Testing
import Foundation
import NotesTestSupport
@testable import NotesCore

@Suite("Export Integration")
struct ExportIntegrationTests {
    @Test func exportsMarkdownWithFrontmatter() async throws {
        let mock = MockNotesService()
        mock.notes = [
            makeSampleAppleNote(
                id: "n1", name: "MD Test",
                bodyPlaintext: "Heading Paragraph",
                folder: "iCloud/Notes"
            ),
        ]

        let tempDir = try makeTempDirectory(prefix: "export-md")
        defer { removeTempDirectory(tempDir) }

        let service = ExportService(notes: mock)
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
        #expect(content.contains("Heading Paragraph"))
    }
}
