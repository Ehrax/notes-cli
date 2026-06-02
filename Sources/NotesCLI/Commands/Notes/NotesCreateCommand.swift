import ArgumentParser
import NotesCore

struct NotesCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note in Apple Notes"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Folder to create the note in; defaults to the scoped account root")
    var folder: String?

    @Option(name: .long, help: "Note title")
    var title: String

    @Option(name: .long, help: "Note body (HTML)")
    var body: String

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        let newID = try await notesSvc.createNote(title: title, bodyHTML: body, folderName: folder ?? "")
        try OutputFormatter.printMessage("Created note \(newID)", format: global.resolvedFormat)
    }
}
