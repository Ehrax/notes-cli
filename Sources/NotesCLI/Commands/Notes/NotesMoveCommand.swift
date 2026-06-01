import ArgumentParser
import NotesCore
import Foundation

struct NotesMoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a note to a different folder"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The note ID to move")
    var id: String

    @Option(name: .long, help: "Destination folder name")
    var to: String

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let safety = try await container.safety
        let notesSvc = try await container.notes
        let db = try await container.database

        // Fetch current note for checkpoint
        guard let note = try await db.fetchNote(id: id) else {
            throw NotesError.noteNotFound(id: id)
        }

        let sourceFolderPath = notesSvc.resolvedFolderPath(note.folderPath)
        let destinationFolderPath = notesSvc.resolvedFolderPath(to)

        // Guard both source and destination folders
        try await safety.guardWrite(toFolder: sourceFolderPath)
        try await safety.guardWrite(toFolder: destinationFolderPath)

        let beforeCheckpoint = Checkpoint(
            noteID: note.id,
            title: note.title,
            bodyProtobuf: note.bodyProtobuf,
            bodyPlaintext: note.bodyPlaintext,
            folderPath: sourceFolderPath
        )

        try await notesSvc.moveNote(id: id, toFolder: destinationFolderPath)
        let storedNote = try await NoteMutationSync.refreshExistingNote(
            id: id,
            fallback: Note(
                id: note.id,
                title: note.title,
                bodyProtobuf: note.bodyProtobuf,
                bodyPlaintext: note.bodyPlaintext,
                folderPath: destinationFolderPath,
                creationDate: note.creationDate,
                modificationDate: note.modificationDate,
                isLocked: note.isLocked,
                syncedAt: Date()
            ),
            notes: notesSvc,
            db: db
        )

        let afterCheckpoint = Checkpoint(
            noteID: storedNote.id,
            title: storedNote.title,
            bodyProtobuf: storedNote.bodyProtobuf,
            bodyPlaintext: storedNote.bodyPlaintext,
            folderPath: storedNote.folderPath
        )

        try await safety.recordAction(
            type: .move,
            noteID: id,
            before: beforeCheckpoint,
            after: afterCheckpoint,
            metadata: ["from": sourceFolderPath, "to": storedNote.folderPath]
        )

        try OutputFormatter.printMessage("Moved note \(id) to \(storedNote.folderPath)", format: global.resolvedFormat)
    }
}
