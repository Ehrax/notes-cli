import ArgumentParser
import NotesCore

struct NotesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Soft-delete a note (moves to Archive)"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The note ID to delete")
    var id: String

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let safety = try await container.safety

        try await safety.softDelete(noteID: id)

        try OutputFormatter.printMessage("Deleted note \(id) (moved to Archive)", format: global.resolvedFormat)
    }
}
