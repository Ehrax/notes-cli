import ArgumentParser
import NotesCore

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export notes to files on disk"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Export file format: json|md")
    var type: ExportFormat = .md

    @Option(name: .long, help: "Output directory (default: ./notes-cli-export/)")
    var output: String = "./notes-cli-export/"

    @Option(name: .long, help: "Filter by folder path")
    var folder: String?

    @Option(name: .long, help: "Comma-separated folders to exclude (e.g. Journal,Documents)")
    var ignoreFolders: String?

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared

        let notesSvc = try await container.notes
        let resolver = try await container.attachmentResolver
        let config = try await container.config.loadConfig()
        let service = ExportService(notes: notesSvc, resolver: resolver)

        let result = try await service.export(
            format: type, outputDir: output,
            folder: folder,
            ignoreFolders: ignoreFolders?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
            scope: config.notes
        )

        if result.exported == 0 && result.skipped == 0 {
            try OutputFormatter.printMessage(
                "No notes matched the given filters.",
                format: global.resolvedFormat
            )
        } else {
            try OutputFormatter.printExportResult(
                result, format: global.resolvedFormat
            )
        }
    }
}

extension ExportFormat: ExpressibleByArgument {}
