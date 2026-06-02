import ArgumentParser
import NotesCore

struct FoldersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folders",
        abstract: "List folders in Apple Notes"
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Render folders as a nested tree")
    var tree = false

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        let folders = try await notesSvc.fetchFolders().map { raw in
            Folder(id: raw.id, name: raw.name, path: raw.path, parentPath: raw.parentPath)
        }

        if tree {
            FolderTree.print(folders)
        } else {
            try OutputFormatter.printFolders(folders, format: global.resolvedFormat)
        }
    }
}

/// Renders a flat folder list as an indented tree by "/"-delimited path depth.
private enum FolderTree {
    static func print(_ folders: [Folder]) {
        let sorted = folders.sorted { $0.path < $1.path }
        for folder in sorted {
            let depth = folder.path.split(separator: "/").count - 1
            let indent = String(repeating: "  ", count: max(0, depth))
            Swift.print("\(indent)\(folder.name)")
        }
    }
}
