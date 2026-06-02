import ArgumentParser
import NotesCore
import Foundation

@main
struct RootCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes-cli",
        abstract: "AI-native Apple Notes CLI",
        discussion: """
        Output is JSON when piped, a table on a TTY; --format json|table|markdown forces one.
        Apple Notes is the source of truth: writes apply immediately, no undo (deletes go to Recently Deleted).
        """,
        version: "0.1.0",
        subcommands: [
            InitCommand.self,
            NotesCommand.self,
            FoldersCommand.self,
            FolderCommand.self,
            ExportCommand.self,
        ]
    )
}

// MARK: - Error handling extension

extension RootCommand {
    static func handleError(_ error: Error) -> ExitCode {
        if let notesError = error as? NotesError {
            FileHandle.standardError.write(
                Data("Error: \(notesError.errorDescription ?? notesError.localizedDescription)\n".utf8)
            )
            return ExitCode(notesError.exitCode)
        } else {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            return ExitCode(2)
        }
    }
}
