import ArgumentParser
import NotesCore

struct LinksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "links",
        abstract: "Show all linked notes for a given note"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Note ID to show links for")
    var noteID: String

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database

        guard try await db.fetchNote(id: noteID) != nil else {
            throw NotesError.noteNotFound(id: noteID)
        }

        let outgoing = try await db.fetchLinks(fromNoteID: noteID)
        let incoming = try await db.fetchLinks(toNoteID: noteID)

        // Combine and deduplicate
        var allLinks: [Link] = []
        var seen = Set<String>()
        for link in outgoing + incoming {
            let key = [link.sourceNoteID, link.targetNoteID].sorted().joined(separator: ":")
            if seen.insert(key).inserted {
                allLinks.append(link)
            }
        }

        try OutputFormatter.printLinks(allLinks, format: global.resolvedFormat)
    }
}
