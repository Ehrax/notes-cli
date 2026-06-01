import ArgumentParser
import NotesCore

struct NotesCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note in Apple Notes"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Folder to create the note in; defaults to the scoped account root/default location")
    var folder: String?

    @Option(name: .long, help: "Note title")
    var title: String

    @Option(name: .long, help: "Note body (HTML)")
    var body: String

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let safety = try await container.safety
        let notesSvc = try await container.notes
        let db = try await container.database
        let resolvedFolderPath = notesSvc.resolvedFolderPath(folder)

        // Guard: check folder is not protected
        try await safety.guardWrite(toFolder: resolvedFolderPath)

        // Create note in Apple Notes
        let newID = try await notesSvc.createNote(title: title, bodyHTML: body, folderName: resolvedFolderPath)

        let storedNote = try await NoteMutationSync.insertCreatedNote(
            id: newID,
            title: title,
            bodyHTML: body,
            folderPath: resolvedFolderPath,
            notes: notesSvc,
            db: db
        )

        // Record the action after the local mirror is coherent.
        let afterCheckpoint = Checkpoint(
            noteID: storedNote.id,
            title: storedNote.title,
            bodyProtobuf: storedNote.bodyProtobuf,
            bodyPlaintext: storedNote.bodyPlaintext,
            folderPath: storedNote.folderPath
        )
        try await safety.recordAction(
            type: .create,
            noteID: newID,
            before: nil,
            after: afterCheckpoint,
            metadata: nil
        )

        try OutputFormatter.printMessage("Created note \(newID)", format: global.resolvedFormat)
    }
}
