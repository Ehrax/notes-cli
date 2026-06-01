import ArgumentParser
import NotesCore

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync Apple Notes to the local database"
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Force a full note-body rebuild instead of metadata-first incremental sync")
    var full = false

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared

        // Always prompt for account selection
        let selected = try await promptAccountSelection(container: container)
        await container.setAccountOverride(selected)

        let syncSvc = try await container.sync
        let result = if full {
            try await syncSvc.fullSync()
        } else {
            try await syncSvc.incrementalSync()
        }
        try OutputFormatter.printSyncResult(result, format: global.resolvedFormat)
    }

    private func promptAccountSelection(container: ServiceContainer) async throws -> String {
        let notesSvc = try await container.notes
        let accounts = try await notesSvc.fetchAccountNames().sorted()

        guard !accounts.isEmpty else {
            throw NotesError.commandFailed(
                message: "No Apple Notes accounts found."
            )
        }

        let defaultAccount = try await notesSvc.fetchDefaultAccountName() ?? accounts[0]

        // If only one account, skip the prompt
        if accounts.count == 1 {
            return accounts[0]
        }

        Swift.print("Select the Apple Notes account to sync:")
        for (index, acct) in accounts.enumerated() {
            let suffix = acct == defaultAccount ? " (default)" : ""
            Swift.print("  \(index + 1). \(acct)\(suffix)")
        }
        Swift.print("Press Enter for \(defaultAccount), or type a number:")
        Swift.print("> ", terminator: "")

        guard let line = readLine(), !line.isEmpty else {
            return defaultAccount
        }

        guard let index = Int(line), accounts.indices.contains(index - 1) else {
            return defaultAccount
        }

        return accounts[index - 1]
    }
}
