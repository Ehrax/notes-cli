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
        let notesSvc = try await container.notes

        guard let raw = try await notesSvc.fetchNote(id: id) else {
            throw NotesError.noteNotFound(id: id)
        }

        let note = Note(from: raw)
        let bodyText = await Self.convertedBody(for: note, container: container)
        try OutputFormatter.printNote(note, bodyText: bodyText, format: global.resolvedFormat)
    }

    private static func convertedBody(for note: Note, container: ServiceContainer) async -> String {
        do {
            let resolver = try await container.attachmentResolver
            return NoteBodyRenderer.markdown(for: note, resolver: resolver)
        } catch {
            return note.bodyPlaintext
        }
    }
}
