import ArgumentParser
import NotesCore

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show action history"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Filter history by note ID")
    var note: String?

    @Option(name: .long, help: "Maximum number of entries to show")
    var limit: Int = 50

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let safety = try await container.safety

        let actions = try await safety.history(noteID: note, limit: limit)

        try OutputFormatter.printHistory(actions, format: global.resolvedFormat)
    }
}
