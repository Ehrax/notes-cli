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
        let notesSvc = try await container.notes
        let configSvc = try await container.config
        let config = try await configSvc.loadConfig()

        var raw = try await notesSvc.fetchAllNoteMetadata()
        if let folder {
            raw = raw.filter { note in
                config.notes.matchesFolderPath(note.folderPath, filter: folder)
            }
        }

        let notes = raw.map { Note(from: $0) }
        try OutputFormatter.printNotes(notes, format: global.resolvedFormat)
    }
}
