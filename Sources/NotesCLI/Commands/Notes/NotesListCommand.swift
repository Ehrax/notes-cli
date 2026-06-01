import ArgumentParser
import NotesCore

struct NotesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all notes, optionally filtered by folder"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Filter notes by folder path")
    var folder: String?

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database
        let configSvc = try await container.config
        let config = try await configSvc.loadConfig()

        let notes: [Note]
        if let folder {
            notes = try await db.fetchAllNotes().filter { note in
                config.notes.matchesFolderPath(note.folderPath, filter: folder)
            }
        } else {
            notes = try await db.fetchAllNotes()
        }

        try OutputFormatter.printNotes(notes, format: global.resolvedFormat)
    }
}
