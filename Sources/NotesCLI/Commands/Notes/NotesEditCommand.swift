import ArgumentParser
import NotesCore
import Foundation

struct NotesEditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a note by ID (opens $EDITOR or uses --title/--body flags)"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The note ID to edit")
    var id: String

    @Option(name: .long, help: "New title for the note")
    var title: String?

    @Option(name: .long, help: "New body (HTML) for the note")
    var body: String?

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let safety = try await container.safety
        let notesSvc = try await container.notes
        let db = try await container.database

        // Fetch current note from DB for checkpoints
        guard let note = try await db.fetchNote(id: id) else {
            throw NotesError.noteNotFound(id: id)
        }

        let sourceFolderPath = notesSvc.resolvedFolderPath(note.folderPath)

        // Safety checks
        try await safety.guardWrite(toFolder: sourceFolderPath)
        try await safety.guardLocked(noteID: id, isLocked: note.isLocked)

        let beforeCheckpoint = Checkpoint(
            noteID: note.id,
            title: note.title,
            bodyProtobuf: note.bodyProtobuf,
            bodyPlaintext: note.bodyPlaintext,
            folderPath: sourceFolderPath
        )

        // Convert protobuf to markdown for editing, falling back to plaintext
        let currentBody = await Self.convertedBody(for: note, container: container)

        let newTitle: String
        let newBody: String

        if title != nil || body != nil {
            // Non-interactive: use provided flags
            newTitle = title ?? note.title
            newBody = body ?? currentBody
        } else {
            // Interactive: open $EDITOR
            let edited = try openEditor(content: currentBody)
            newTitle = note.title
            newBody = edited
        }

        try await notesSvc.updateNote(id: id, title: newTitle, bodyHTML: newBody)
        let storedNote = try await NoteMutationSync.refreshExistingNote(
            id: id,
            fallback: Note(
                id: note.id,
                title: newTitle,
                bodyProtobuf: Data(),
                bodyPlaintext: "",
                folderPath: sourceFolderPath,
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
            type: .edit,
            noteID: id,
            before: beforeCheckpoint,
            after: afterCheckpoint,
            metadata: nil
        )

        try OutputFormatter.printMessage("Updated note \(id)", format: global.resolvedFormat)
    }

    /// Convert protobuf to markdown, falling back to bodyPlaintext on failure or empty data.
    private static func convertedBody(for note: Note, container: ServiceContainer) async -> String {
        guard !note.bodyProtobuf.isEmpty else {
            return note.bodyPlaintext
        }
        do {
            let resolver = try await container.attachmentResolver
            let result = try ProtobufToMarkdown.convert(data: note.bodyProtobuf, resolver: resolver)
            return result.markdown
        } catch {
            Log.debug(
                "Protobuf conversion failed for note \(note.id), falling back to plaintext: \(error)",
                logger: Log.general
            )
            return note.bodyPlaintext
        }
    }

    private func openEditor(content: String) throws -> String {
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("notes-cli-edit-\(UUID().uuidString).txt")

        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, tempFile.path]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NotesError.commandFailed(message: "Editor exited with status \(process.terminationStatus)")
        }

        return try String(contentsOf: tempFile, encoding: .utf8)
    }
}
