import ArgumentParser
import NotesCore

struct NotesSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search notes using full-text search"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Filter by tag name")
    var tag: String?

    @Option(name: .long, help: "Filter by folder path")
    var folder: String?

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database
        let configSvc = try await container.config
        let config = try await configSvc.loadConfig()

        var results = try await db.searchNotes(query: query)

        // Apply optional filters
        if let folder {
            results = results.filter { note in
                config.notes.matchesFolderPath(note.folderPath, filter: folder)
            }
        }

        if let tagName = tag {
            // Filter notes that have the specified tag
            let matchedTag = try await db.fetchTag(name: tagName)
            if let matchedTag, let tagID = matchedTag.id {
                let taggedNotes = try await db.fetchNotes(forTagID: tagID)
                let taggedIDs = Set(taggedNotes.map(\.id))
                results = results.filter { taggedIDs.contains($0.id) }
            } else {
                results = []
            }
        }

        try OutputFormatter.printNotes(results, format: global.resolvedFormat)
    }
}
