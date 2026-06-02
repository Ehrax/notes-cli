import Testing
@testable import NotesCore

@Suite("FolderMovePlanner")
struct FolderMovePlannerTests {

    private typealias Note = FolderMovePlanner.NoteRef

    @Test("leaf folder: recreate under new parent, move its note, delete source")
    func leafMove() throws {
        let plan = try FolderMovePlanner.plan(
            source: "A/Foo",
            destParent: "B",
            subtreeFolders: ["A/Foo"],
            notes: [Note(id: "n1", folder: "A/Foo")]
        )
        #expect(plan.creates == [.init(name: "Foo", parent: "B")])
        #expect(plan.moves == [.init(id: "n1", toFolder: "B/Foo")])
        #expect(plan.delete == "A/Foo")
    }

    @Test("move to account root: parent is nil")
    func moveToRoot() throws {
        let plan = try FolderMovePlanner.plan(
            source: "A/Foo", destParent: nil,
            subtreeFolders: ["A/Foo"], notes: [Note(id: "n1", folder: "A/Foo")]
        )
        #expect(plan.creates == [.init(name: "Foo", parent: nil)])
        #expect(plan.moves == [.init(id: "n1", toFolder: "Foo")])
    }

    @Test("nested subtree: parents created before children, notes remapped")
    func nestedSubtree() throws {
        let plan = try FolderMovePlanner.plan(
            source: "A/Foo",
            destParent: "B",
            subtreeFolders: ["A/Foo/Sub", "A/Foo"],   // unordered on purpose
            notes: [Note(id: "n2", folder: "A/Foo/Sub"), Note(id: "n1", folder: "A/Foo")]
        )
        // Shallowest first so the parent exists before its child.
        #expect(plan.creates == [
            .init(name: "Foo", parent: "B"),
            .init(name: "Sub", parent: "B/Foo"),
        ])
        #expect(plan.moves.contains(.init(id: "n1", toFolder: "B/Foo")))
        #expect(plan.moves.contains(.init(id: "n2", toFolder: "B/Foo/Sub")))
        #expect(plan.delete == "A/Foo")
    }

    @Test("moving a folder into its own subtree is rejected")
    func intoOwnSubtree() {
        #expect(throws: FolderMovePlanner.PlanError.intoOwnSubtree) {
            try FolderMovePlanner.plan(
                source: "A/Foo", destParent: "A/Foo/Sub",
                subtreeFolders: ["A/Foo", "A/Foo/Sub"], notes: []
            )
        }
    }

    @Test("moving a folder to the parent it already lives in is rejected")
    func alreadyAtDestination() {
        #expect(throws: FolderMovePlanner.PlanError.alreadyAtDestination) {
            try FolderMovePlanner.plan(
                source: "A/Foo", destParent: "A",
                subtreeFolders: ["A/Foo"], notes: []
            )
        }
    }

    @Test("unknown source folder is rejected")
    func sourceNotFound() {
        #expect(throws: FolderMovePlanner.PlanError.sourceNotFound) {
            try FolderMovePlanner.plan(
                source: "A/Ghost", destParent: "B",
                subtreeFolders: ["A/Foo"], notes: []
            )
        }
    }
}
