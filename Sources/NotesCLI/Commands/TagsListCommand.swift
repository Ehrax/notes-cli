import ArgumentParser
import NotesCore

struct TagsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List all tags"
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database

        let tags = try await db.fetchAllTags()
        try OutputFormatter.printTags(tags, format: global.resolvedFormat)
    }
}
