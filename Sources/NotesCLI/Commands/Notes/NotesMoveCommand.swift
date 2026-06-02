import ArgumentParser
import NotesCore

struct NotesMoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a note to a different folder"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The note ID to move")
    var id: String

    @Option(name: .long, help: "Destination folder path")
    var folder: String

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        try await notesSvc.moveNote(id: id, toFolder: folder)
        try OutputFormatter.printMessage("Moved note \(id) to \(folder)", format: global.resolvedFormat)
    }
}
