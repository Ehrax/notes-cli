import ArgumentParser
import Darwin
import NotesCore
import Foundation

struct NotesEditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a note by ID (opens $EDITOR, or uses --title/--body flags)",
        discussion: """
        Pass --title and/or --body to edit non-interactively (required for agents and pipes).
        With no flags it opens $EDITOR seeded with the current body, which needs a TTY.

        --body is HTML (see `notes create --help` for honored tags).
        With --body, --title becomes the note's first line; --title alone updates the name only.
        """
    )

    /// Test seam: overrides the real TTY probe when set; `nil` falls back to `isatty(STDIN)`.
    nonisolated(unsafe) static var interactiveOverride: Bool?

    @OptionGroup var global: GlobalOptions

    @Argument(help: "The note ID to edit")
    var id: String

    @Option(
        name: .long,
        help: ArgumentHelp(
            "New title. With --body it becomes the note's first line; "
                + "alone it updates the note's name only."
        )
    )
    var title: String?

    @Option(name: .long, help: "New body as HTML (see `notes create --help` for honored tags)")
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
            // No flags: opening $EDITOR needs a TTY. Refuse non-interactive callers (agents,
            // pipes, /dev/null stdin) with a clear error rather than blocking on an editor.
            let interactive = Self.interactiveOverride ?? (isatty(STDIN_FILENO) != 0)
            guard interactive else {
                throw NotesError.commandFailed(
                    message: "notes edit requires --title and/or --body when run non-interactively; "
                        + "an interactive $EDITOR session needs a TTY."
                )
            }
            // Interactive: open $EDITOR seeded with the note's current markdown body.
            guard let raw = try await notesSvc.fetchNote(id: id) else {
                throw NotesError.noteNotFound(id: id)
            }
            let current = try await notesSvc.renderMarkdownBody(for: raw)
            newTitle = nil
            newBody = NoteHTML.plainTextHTML(try openEditor(content: current))
        }

        try await notesSvc.updateNote(id: id, title: newTitle, bodyHTML: newBody)
        try OutputFormatter.printMessage("Updated note \(id)", format: global.resolvedFormat)
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
