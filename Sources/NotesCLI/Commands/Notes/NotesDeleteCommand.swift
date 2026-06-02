import ArgumentParser
import NotesCore

struct NotesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a note (moves to Apple's Recently Deleted)"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The note ID to delete")
    var id: String

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        try await notesSvc.deleteNote(id: id)
        try OutputFormatter.printMessage("Deleted note \(id)", format: global.resolvedFormat)
    }
}
