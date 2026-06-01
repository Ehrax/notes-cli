import ArgumentParser
import NotesCore

struct NotesReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a note by ID"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The note ID to read")
    var id: String

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database

        guard let note = try await db.fetchNote(id: id) else {
            throw NotesError.noteNotFound(id: id)
        }

        let bodyText = await Self.convertedBody(for: note, container: container)
        try OutputFormatter.printNote(note, bodyText: bodyText, format: global.resolvedFormat)
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
}
