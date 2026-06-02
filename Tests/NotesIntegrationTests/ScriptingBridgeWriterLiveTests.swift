import Foundation
import Testing
import NotesCore

/// Live ScriptingBridge write round-trip against real Apple Notes, through the real
/// `ScriptingBridgeWriter` (Swift wrapper → ObjC over the generated SB interface).
///
/// Gated by `NOTES_CLI_LIVE_TESTS=1`; otherwise it no-ops so `make test` never touches Notes.
/// Every write is scoped to a uniquely-named `notes-cli-test-<uuid>` folder, and the suite
/// deletes that folder at the end — so real notes are never touched. Requires Full Disk
/// Access (reads) + Automation (writes).
@Suite("ScriptingBridge Writer (live)", .serialized)
struct ScriptingBridgeWriterLiveTests {

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
        var last: AppleNoteRaw? = try reader.fetchNote(id: id)
        while !predicate(last) && waited < timeoutMs {
            try await Task.sleep(for: .milliseconds(250))
            waited += 250
            last = try reader.fetchNote(id: id)
        }
        return last
    }

    private func waitForFolders(
        _ reader: NoteStoreReader,
        timeoutMs: Int = 30000,
        until predicate: @escaping ([AppleFolderRaw]) -> Bool
    ) async throws -> Bool {
        var waited = 0
        while waited < timeoutMs {
            if predicate(try reader.fetchFolders()) { return true }
            try await Task.sleep(for: .milliseconds(500))
            waited += 500
        }
        return predicate(try reader.fetchFolders())
    }

    @Test("note create → read-back → edit → move → delete round-trip")
    func noteRoundTrip() async throws {
        guard liveEnabled else { return }
        let writer = await ScriptingBridgeWriter(scope: .default)
        guard try await writer.isAvailable() else {
            Issue.record("Notes/Automation unavailable")
            return
        }
        let reader = NoteStoreReader()
        let suffix = String(UUID().uuidString.prefix(8))
        let root = "notes-cli-test-\(suffix)"
        let sub = "moved"
        try await writer.createFolder(name: root, parentName: nil)
        try await writer.createFolder(name: sub, parentName: root)
        defer { Task { try? await writer.deleteFolder(path: root) } }

        let id = try await writer.createNote(
            title: "SB roundtrip \(suffix)",
            bodyHTML: "<div>SB roundtrip \(suffix)</div><div>hello-sb</div>",
            folderName: root
        )
        #expect(id.hasPrefix("x-coredata://"))
        let created = try await waitForNote(reader, id: id) { $0?.folderPath.hasSuffix(root) ?? false }
        #expect(created?.folderPath.hasSuffix(root) == true)

        try await writer.updateNote(id: id, title: nil, bodyHTML: "<div>SB edited \(suffix)</div><div>body</div>")
        let edited = try await waitForNote(reader, id: id) { ($0?.bodyPlaintext.contains("SB edited \(suffix)")) ?? false }
        #expect(edited?.bodyPlaintext.contains("SB edited \(suffix)") == true)

        try await writer.moveNote(id: id, toFolder: "\(root)/\(sub)")
        let moved = try await waitForNote(reader, id: id) { $0?.folderPath.hasSuffix("\(root)/\(sub)") ?? false }
        #expect(moved?.folderPath.hasSuffix("\(root)/\(sub)") == true)

        try await writer.deleteNote(id: id)
        let gone = try await waitForNote(reader, id: id) { $0 == nil }
        #expect(gone == nil)
    }

    @Test("folder create → rename → delete round-trip")
    func folderRoundTrip() async throws {
        guard liveEnabled else { return }
        let writer = await ScriptingBridgeWriter(scope: .default)
        guard try await writer.isAvailable() else {
            Issue.record("Notes/Automation unavailable")
            return
        }
        let reader = NoteStoreReader()
        let suffix = String(UUID().uuidString.prefix(8))
        let root = "notes-cli-test-\(suffix)"
        let renamed = "\(root)-renamed"

        try await writer.createFolder(name: root, parentName: nil)
        #expect(try await waitForFolders(reader) { $0.contains { $0.path.hasSuffix(root) } })

        try await writer.renameFolder(path: root, newName: renamed)
        #expect(try await waitForFolders(reader) { $0.contains { $0.path.hasSuffix(renamed) } })

        // delete the renamed folder; it must vanish from live reads (ZMARKEDFORDELETION filter)
        try await writer.deleteFolder(path: renamed)
        #expect(try await waitForFolders(reader) { folders in !folders.contains { $0.path.contains(suffix) } })
    }

    @Test("folder move recreates the subtree, relocates notes (ids preserved), deletes source")
    func folderMoveRoundTrip() async throws {
        guard liveEnabled else { return }
        let writer = await ScriptingBridgeWriter(scope: .default)
        guard try await writer.isAvailable() else {
            Issue.record("Notes/Automation unavailable")
            return
        }
        let reader = NoteStoreReader()
        let service = DirectNotesService(reader: reader, writer: writer, scope: .default, aiFooterEnabled: false)
        let suffix = String(UUID().uuidString.prefix(8))
        let root = "notes-cli-test-\(suffix)"
        try await writer.createFolder(name: root, parentName: nil)
        try await writer.createFolder(name: "dest", parentName: root)
        try await writer.createFolder(name: "mover", parentName: root)
        try await writer.createFolder(name: "sub", parentName: "\(root)/mover")
        defer { Task { try? await writer.deleteFolder(path: root) } }

        // A note in the folder and one in its subfolder — both must travel with the move.
        let topNote = try await writer.createNote(
            title: "top \(suffix)", bodyHTML: "<div>top</div>", folderName: "\(root)/mover"
        )
        let subNote = try await writer.createNote(
            title: "sub \(suffix)", bodyHTML: "<div>sub</div>", folderName: "\(root)/mover/sub"
        )
        _ = try await waitForNote(reader, id: topNote) { $0?.folderPath.hasSuffix("\(root)/mover") ?? false }
        _ = try await waitForNote(reader, id: subNote) { $0?.folderPath.hasSuffix("\(root)/mover/sub") ?? false }

        // Move `mover` (its note + subfolder + subnote) under `dest`.
        try await service.moveFolder(path: "\(root)/mover", toParent: "\(root)/dest")

        // Subtree recreated under dest; the original source folder is gone.
        #expect(try await waitForFolders(reader) { folders in
            folders.contains { $0.path.hasSuffix("\(root)/dest/mover/sub") }
                && !folders.contains { $0.path.hasSuffix("\(root)/mover") }
        })

        // Notes relocated under the same ids — moveNote preserves identity.
        let movedTop = try await waitForNote(reader, id: topNote) { $0?.folderPath.hasSuffix("\(root)/dest/mover") ?? false }
        #expect(movedTop?.folderPath.hasSuffix("\(root)/dest/mover") == true)
        let movedSub = try await waitForNote(reader, id: subNote) { $0?.folderPath.hasSuffix("\(root)/dest/mover/sub") ?? false }
        #expect(movedSub?.folderPath.hasSuffix("\(root)/dest/mover/sub") == true)
    }
}
