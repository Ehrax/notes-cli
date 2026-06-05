import Foundation
import Testing
import NotesTestSupport
@testable import NotesCore

/// Live export round-trip against real Apple Notes: write a folder + note through the real
/// ScriptingBridge path, export just that folder to a temp dir, and verify the on-disk
/// Markdown/JSON reflects what was written (body fidelity + folder structure).
///
/// Gated by `NOTES_CLI_LIVE_TESTS=1`; otherwise no-ops so `make test` never touches Notes.
/// Scoped to a unique `notes-cli-test-<uuid>` folder and cleaned up. Requires Full Disk
/// Access (reads) + Automation (writes).
///
/// Attachment-copy fidelity (`assets/`) is *not* covered here: the write path can only set an
/// HTML body, never attach files, so no live note can carry an attachment. That path stays
/// covered by the mock-based `ExportService` unit tests.
@Suite("Export (live)", .serialized)
struct ExportLiveTests {

    private var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["NOTES_CLI_LIVE_TESTS"] == "1"
    }

    /// Poll the live reader until `predicate` holds (write visibility lags via WAL — R3).
    private func waitForNote(
        _ reader: NoteStoreReader,
        id: String,
        timeoutMs: Int = 10000,
        until predicate: @escaping (AppleNoteRaw?) -> Bool
    ) async throws -> AppleNoteRaw? {
        var waited = 0
        var last = try reader.fetchNote(id: id)
        while !predicate(last) && waited < timeoutMs {
            try await Task.sleep(for: .milliseconds(250))
            waited += 250
            last = try reader.fetchNote(id: id)
        }
        return last
    }

    @Test("export md + json reflect a freshly written note and its folder")
    func exportLiveRoundTrip() async throws {
        guard liveEnabled else { return }
        let reader = NoteStoreReader()
        let writer = await ScriptingBridgeWriter(scope: .default)
        guard try await writer.isAvailable() else {
            Issue.record("Notes/Automation unavailable")
            return
        }
        // Footer off so the exported body is deterministic for assertions.
        let service = DirectNotesService(
            reader: reader, writer: writer, scope: .default, aiFooterEnabled: false
        )

        let suffix = String(UUID().uuidString.prefix(8))
        let root = "notes-cli-test-\(suffix)"
        let marker = "export-marker-\(suffix)"
        try await writer.createFolder(name: root, parentName: nil)
        defer { Task { try? await writer.deleteFolder(path: root) } }

        let id = try await service.createNote(
            title: "Export Probe \(suffix)",
            bodyHTML: "<div>\(marker) with <b>bold</b> and <i>emphasis</i> text.</div><ul><li>one</li><li>two</li></ul>",
            folderName: root,
            agent: nil
        )
        _ = try await waitForNote(reader, id: id) { ($0?.bodyPlaintext.contains(marker)) ?? false }

        let tempDir = try makeTempDirectory(prefix: "export-live")
        defer { removeTempDirectory(tempDir) }
        let export = ExportService(notes: service)

        // Markdown: front-matter + body fidelity (italic round-trips as *emphasis*).
        let md = try await export.export(format: .md, outputDir: tempDir.path, folder: root)
        #expect(md.exported == 1)
        let mdContent = try String(contentsOf: locateExport(in: tempDir, root: root, ext: "md"), encoding: .utf8)
        #expect(mdContent.hasPrefix("---\n"))
        #expect(mdContent.contains("title: \"Export Probe \(suffix)\""))
        #expect(mdContent.contains(marker))
        #expect(mdContent.contains("*emphasis*"))
        #expect(mdContent.contains("- one"))

        // JSON: stable shape carries title, body, and the note's folder path.
        let json = try await export.export(format: .json, outputDir: tempDir.path, folder: root)
        #expect(json.exported == 1)
        let jsonData = try Data(contentsOf: locateExport(in: tempDir, root: root, ext: "json"))
        let decoded = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        #expect(decoded?["title"] as? String == "Export Probe \(suffix)")
        #expect((decoded?["body"] as? String)?.contains(marker) == true)
        #expect((decoded?["folderPath"] as? String)?.contains(root) == true)
    }

    /// Locate the single exported file for our test folder by extension.
    private func locateExport(in tempDir: URL, root: String, ext: String) throws -> URL {
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == ext, url.deletingLastPathComponent().path.contains(root) {
                return url
            }
        }
        throw NotesError.commandFailed(message: "no .\(ext) export found for \(root)")
    }
}
