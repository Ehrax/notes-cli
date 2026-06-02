import Foundation

/// Pure planner for relocating a folder subtree.
///
/// Apple Notes' scripting `move` command deletes a folder instead of re-parenting it, and
/// `container` is read-only (ADR 0002), so there is no one-call folder move. A folder move is
/// therefore a *recreate-and-move-notes* plan: recreate the source folder and its descendants
/// under the new parent, move every note in (note moves preserve their ids), then delete the
/// emptied source.
///
/// All paths are account-relative ("/"-delimited, no account prefix). The planner is pure;
/// `DirectNotesService` resolves scope, gathers the subtree, and executes the plan.
enum FolderMovePlanner {

    struct Plan: Equatable {
        struct FolderCreate: Equatable {
            let name: String
            let parent: String?
        }
        struct NoteMove: Equatable {
            let id: String
            let toFolder: String
        }
        /// Folders to create, shallowest-first so each parent exists before its children.
        let creates: [FolderCreate]
        /// Notes to relocate into their recreated folders (ids are preserved by the move).
        let moves: [NoteMove]
        /// The source folder to delete once its notes have been moved out.
        let delete: String
    }

    struct NoteRef: Equatable {
        let id: String
        let folder: String
        init(id: String, folder: String) {
            self.id = id
            self.folder = folder
        }
    }

    enum PlanError: Error, Equatable {
        case sourceNotFound
        case alreadyAtDestination
        case intoOwnSubtree
    }

    /// Build the plan. `subtreeFolders` must contain `source` and all its descendants;
    /// `notes` are the notes that live anywhere in that subtree.
    static func plan(
        source: String,
        destParent: String?,
        subtreeFolders: [String],
        notes: [NoteRef]
    ) throws -> Plan {
        let src = normalize(source)
        guard subtreeFolders.map(normalize).contains(src),
              let leaf = src.split(separator: "/").last.map(String.init) else {
            throw PlanError.sourceNotFound
        }

        let parent = destParent.map(normalize).flatMap { $0.isEmpty ? nil : $0 }
        let newRoot = parent.map { "\($0)/\(leaf)" } ?? leaf
        guard newRoot != src else { throw PlanError.alreadyAtDestination }
        guard !newRoot.hasPrefix(src + "/") else { throw PlanError.intoOwnSubtree }

        let creates = makeCreates(subtreeFolders.map(normalize), src: src, newRoot: newRoot)
        let moves = notes.map {
            Plan.NoteMove(id: $0.id, toFolder: remap($0.folder, src: src, newRoot: newRoot))
        }
        return Plan(creates: creates, moves: moves, delete: src)
    }

    // MARK: - Helpers

    private static func makeCreates(_ folders: [String], src: String, newRoot: String) -> [Plan.FolderCreate] {
        folders
            .map { remap($0, src: src, newRoot: newRoot) }
            .sorted { $0.split(separator: "/").count < $1.split(separator: "/").count }
            .map { newPath in
                let comps = newPath.split(separator: "/").map(String.init)
                let parent = comps.dropLast().joined(separator: "/")
                return Plan.FolderCreate(name: comps.last ?? newPath, parent: parent.isEmpty ? nil : parent)
            }
    }

    /// Replace the `src` prefix of an account-relative path with `newRoot`.
    private static func remap(_ path: String, src: String, newRoot: String) -> String {
        let normalized = normalize(path)
        if normalized == src { return newRoot }
        return newRoot + String(normalized.dropFirst(src.count))   // dropFirst keeps the leading "/"
    }

    private static func normalize(_ path: String) -> String {
        var result = path.trimmingCharacters(in: .whitespaces)
        while result.hasPrefix("/") { result.removeFirst() }
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
