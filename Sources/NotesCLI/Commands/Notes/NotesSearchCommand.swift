import ArgumentParser
import NotesCore

struct NotesSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search notes by title and body content"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Filter by folder path")
    var folder: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int = 50

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let notesSvc = try await container.notes
        let configSvc = try await container.config
        let config = try await configSvc.loadConfig()

        var raw = try await notesSvc.searchNotes(query: query, limit: limit)
        if let folder {
            raw = raw.filter { note in
                config.notes.matchesFolderPath(note.folderPath, filter: folder)
            }
        }

        let results = raw.map { Note(from: $0) }
        try OutputFormatter.printNotes(results, format: global.resolvedFormat)
    }
}
