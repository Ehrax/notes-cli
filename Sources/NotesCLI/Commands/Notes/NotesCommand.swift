import ArgumentParser

struct NotesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes",
        abstract: "Manage notes",
        discussion: """
        Note IDs are the `id` field from `notes list` / `notes search`; pass that to read, edit, delete, and move.
        Folder paths are `/`-separated (e.g. Projects/Ideas), relative to the account chosen by `init`.
        Bodies are HTML (<h1>, <b>, <i>, <ul>, <a>…); pass the title via --title, not in the body.

        Example:
          notes search Spec --format json    # find the note's id
          notes read <id> --format json
          notes edit <id> --body '<div>Updated</div>'
        """,
        subcommands: [
            NotesListCommand.self,
            NotesReadCommand.self,
            NotesCreateCommand.self,
            NotesEditCommand.self,
            NotesDeleteCommand.self,
            NotesMoveCommand.self,
            NotesSearchCommand.self,
        ]
    )
}
