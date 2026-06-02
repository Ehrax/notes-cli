import ArgumentParser
import NotesCore
import Foundation

struct NotesEditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a note by ID (opens $EDITOR, or uses --title/--body flags)"
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
        let notesSvc = try await container.notes

        let newTitle: String?
        let newBody: String?

        if title != nil || body != nil {
            // Non-interactive: apply the provided flags (nil leaves that field unchanged).
            newTitle = title
            newBody = body
        } else {
            // Interactive: open $EDITOR seeded with the note's current markdown body.
            guard let raw = try await notesSvc.fetchNote(id: id) else {
                throw NotesError.noteNotFound(id: id)
            }
            let current = await Self.convertedBody(for: Note(from: raw), container: container)
            newTitle = nil
            newBody = try openEditor(content: current)
        }

        try await notesSvc.updateNote(id: id, title: newTitle, bodyHTML: newBody)
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
