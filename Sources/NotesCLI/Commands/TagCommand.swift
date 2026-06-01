import ArgumentParser
import NotesCore

struct TagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Add tags to a note"
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Note ID to tag")
    var noteID: String

    @Argument(parsing: .remaining, help: "Tag names to add")
    var tagNames: [String]

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database
        let safety = try await container.safety

        guard try await db.fetchNote(id: noteID) != nil else {
            throw NotesError.noteNotFound(id: noteID)
        }

        var addedTags: [String] = []

        for name in tagNames {
            // Find or create the tag
            let tag: Tag
            if let existing = try await db.fetchTag(name: name) {
                tag = existing
            } else {
                tag = try await db.insertTag(Tag(name: name))
            }

            guard let tagID = tag.id else { continue }

            // Associate with note
            try await db.addTag(noteID: noteID, tagID: tagID)
            addedTags.append(name)
        }

        try await safety.recordAction(
            type: .tag,
            noteID: noteID,
            before: nil,
            after: nil,
            metadata: ["tags": addedTags.joined(separator: ",")]
        )

        try OutputFormatter.printMessage(
            "Tagged note \(noteID) with: \(addedTags.joined(separator: ", "))",
            format: global.resolvedFormat
        )
    }
}
