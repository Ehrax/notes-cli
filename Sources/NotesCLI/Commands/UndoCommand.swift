import ArgumentParser
import NotesCore

struct UndoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "undo",
        abstract: "Undo the last action"
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let safety = try await container.safety

        guard let result = try await safety.undoLast() else {
            throw NotesError.nothingToUndo
        }

        try OutputFormatter.printUndoResult(result, format: global.resolvedFormat)
    }
}
