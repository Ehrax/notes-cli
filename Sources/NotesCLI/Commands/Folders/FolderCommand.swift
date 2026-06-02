import ArgumentParser
import NotesCore

struct FolderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folder",
        abstract: "Create, rename, move, or delete folders",
        discussion: "Folder paths are `/`-separated (e.g. Projects/Ideas), relative to the account chosen by `init`.",
        subcommands: [
            FolderCreateCommand.self,
            FolderRenameCommand.self,
            FolderMoveCommand.self,
            FolderDeleteCommand.self,
        ]
    )
}

struct FolderCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new folder"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Name of the folder to create")
    var name: String

    @Option(name: .long, help: "Parent folder path; defaults to the scoped account root")
    var parent: String?

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        try await notesSvc.createFolder(name: name, parentName: parent)
        try OutputFormatter.printMessage("Created folder \(name)", format: global.resolvedFormat)
    }
}

struct FolderRenameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a folder"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Path of the folder to rename")
    var path: String

    @Argument(help: "New name for the folder")
    var newName: String

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        try await notesSvc.renameFolder(path: path, newName: newName)
        try OutputFormatter.printMessage("Renamed folder \(path) to \(newName)", format: global.resolvedFormat)
    }
}

struct FolderMoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a folder to a different parent"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Path of the folder to move")
    var path: String

    @Option(name: .long, help: "Destination parent path; defaults to the scoped account root")
    var parent: String?

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        try await notesSvc.moveFolder(path: path, toParent: parent)
        try OutputFormatter.printMessage("Moved folder \(path)", format: global.resolvedFormat)
    }
}

struct FolderDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a folder (moves to Recently Deleted)"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Path of the folder to delete")
    var path: String

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        try await notesSvc.deleteFolder(path: path)
        try OutputFormatter.printMessage("Deleted folder \(path)", format: global.resolvedFormat)
    }
}
