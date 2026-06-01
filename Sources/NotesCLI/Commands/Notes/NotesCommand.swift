import ArgumentParser

struct NotesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes",
        abstract: "Manage notes",
        subcommands: [
            NotesListCommand.self,
            NotesReadCommand.self,
            NotesCreateCommand.self,
            NotesEditCommand.self,
            NotesDeleteCommand.self,
            NotesMoveCommand.self,
            NotesSearchCommand.self,
        ],
        defaultSubcommand: NotesListCommand.self
    )
}
