import ArgumentParser
import NotesCore
import Darwin

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Output format: json, table, or markdown")
    var format: OutputFormat?

    @Flag(name: [.long, .customShort("v")], help: "Enable verbose debug output on stderr")
    var verbose: Bool = false

    var resolvedFormat: OutputFormat {
        if let format { return format }
        return isatty(STDOUT_FILENO) != 0 ? .table : .json
    }

    func configureLogging() {
        Log.isVerbose = verbose
    }
}

enum OutputFormat: String, ExpressibleByArgument, Sendable, CaseIterable {
    case json
    case table
    case markdown
}
