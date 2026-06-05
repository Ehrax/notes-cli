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
            try OutputFormatter.printFolderTree(folders, format: global.resolvedFormat)
        } else {
            try OutputFormatter.printFolders(folders, format: global.resolvedFormat)
        }
    }
}
