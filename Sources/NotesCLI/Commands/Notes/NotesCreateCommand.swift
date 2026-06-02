import ArgumentParser
import NotesCore

struct NotesCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note in Apple Notes",
        discussion: """
        --body is raw HTML, passed straight to Apple Notes.
        Honored tags: <h1>/<h2>/<h3> headings; <b> <i> <u>; <ul>/<ol>/<li> lists;
        <a href> links; <br>, <div>, <p> for line breaks. CSS, classes, and colors are ignored.
        --title becomes the note's first line for you — don't repeat it in --body.
        A 🤖 "created by AI" footer is appended unless disabled (notes-cli init --no-ai-footer);
        pass --agent or set $NOTES_CLI_AGENT to name the model.

        Example:
          notes create --title "Peniche" --body "<div>Fishing town, <b>great</b> waves.</div>"
        """
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Folder to create the note in; defaults to the scoped account root")
    var folder: String?

    @Option(name: .long, help: "Note title; rendered as the note's first line")
    var title: String

    @Option(name: .long, help: "Note body as HTML (see the command help for honored tags)")
    var body: String

    @Option(name: .long, help: "Model/agent name for the AI footer (overrides $NOTES_CLI_AGENT)")
    var agent: String?

    func run() async throws {
        global.configureLogging()
        let notesSvc = try await ServiceContainer.shared.notes
        let newID = try await notesSvc.createNote(
            title: title, bodyHTML: body, folderName: folder ?? "", agent: agent
        )
        try OutputFormatter.printMessage("Created note \(newID)", format: global.resolvedFormat)
    }
}
