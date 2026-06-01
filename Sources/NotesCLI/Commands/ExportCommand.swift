import ArgumentParser
import NotesCore

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export notes to files on disk"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Export file format: md")
    var type: ExportFormat = .md

    @Option(name: .long, help: "Output directory (default: ./notes-cli-export/)")
    var output: String = "./notes-cli-export/"

    @Flag(name: .long, help: "Run an incremental sync before exporting")
    var live = false

    @Option(name: .long, help: "Filter by account name")
    var account: String?

    @Option(name: .long, help: "Filter by folder path")
    var folder: String?

    @Option(name: .long, help: "Filter by tag name")
    var tag: String?

    @Option(name: .long, help: "Comma-separated folders to exclude (e.g. Journal,Documents)")
    var ignoreFolders: String?

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared

        if live {
            let syncSvc = try await container.sync
            let syncResult = try await syncSvc.incrementalSync()
            Log.debug(
                "Pre-export sync: +\(syncResult.added) ~\(syncResult.updated) -\(syncResult.deleted)",
                logger: Log.general
            )
        }

        let db = try await container.database
        let resolver = try await container.attachmentResolver
        let service = ExportService(db: db, resolver: resolver)

        let result = try await service.export(
            format: type, outputDir: output,
            account: account, folder: folder, tag: tag,
            ignoreFolders: ignoreFolders?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
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
