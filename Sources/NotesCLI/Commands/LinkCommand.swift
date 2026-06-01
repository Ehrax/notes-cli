import ArgumentParser
import NotesCore

struct LinkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "Create a bidirectional link between two notes"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Source note ID")
    var sourceID: String

    @Argument(help: "Target note ID")
    var targetID: String

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database
        let safety = try await container.safety

        // Verify both notes exist
        guard try await db.fetchNote(id: sourceID) != nil else {
            throw NotesError.noteNotFound(id: sourceID)
        }
        guard try await db.fetchNote(id: targetID) != nil else {
            throw NotesError.noteNotFound(id: targetID)
        }

        // Create bidirectional links
        let forwardLink = Link(sourceNoteID: sourceID, targetNoteID: targetID)
        _ = try await db.insertLink(forwardLink)

        let backLink = Link(sourceNoteID: targetID, targetNoteID: sourceID)
        _ = try await db.insertLink(backLink)

        // Record actions
        try await safety.recordAction(
            type: .link,
            noteID: sourceID,
            before: nil,
            after: nil,
            metadata: ["target": targetID]
        )

        try OutputFormatter.printMessage(
            "Linked \(sourceID) <-> \(targetID)",
            format: global.resolvedFormat
        )
    }
}
