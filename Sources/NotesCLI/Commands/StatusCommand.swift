import ArgumentParser
import NotesCore
import Foundation

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show database stats: note count, folder count, last sync time"
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let db = try await container.database

        let notes = try await db.fetchAllNotes()
        let folders = try await db.fetchAllFolders()
        let lastSyncValue = try await db.getSyncState(key: SyncService.lastSyncKey)

        let status = StatusInfo(
            noteCount: notes.count,
            folderCount: folders.count,
            lastSync: lastSyncValue ?? "never"
        )

        switch global.resolvedFormat {
        case .json:
            try OutputFormatter.print(status, format: .json)
        case .table:
            print("Notes:     \(status.noteCount)")
            print("Folders:   \(status.folderCount)")
            print("Last sync: \(status.lastSync)")
        case .markdown:
            try OutputFormatter.print(status, format: .markdown)
        }
    }
}

private struct StatusInfo: Codable, Sendable {
    let noteCount: Int
    let folderCount: Int
    let lastSync: String
}
