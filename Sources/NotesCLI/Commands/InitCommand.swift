import ArgumentParser
import NotesCore
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize notes-cli: pick an Apple Notes account and write ~/.notes-cli/config.json"
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .long, help: "Non-interactive mode, accept all defaults (for AI agents)")
    var yes = false

    @Flag(name: .long, help: "Don't append the italic 'created by AI' footer to new notes")
    var noAiFooter = false

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let configSvc = try await container.config

        // Ensure ~/.notes-cli/ directory exists
        _ = try configSvc.notesDirectory()
        let defaultAccount = try await resolveNotesAccountSelectionWithFallback()
        let accounts = try await resolveNotesAccountsWithFallback(default: defaultAccount)

        var config = Config.default
        config.aiFooterEnabled = !noAiFooter
        if yes {
            config.notes.selectedAccount = defaultAccount
        } else {
            config.notes.selectedAccount = promptNotesAccount(accounts: accounts, defaultAccount: defaultAccount)
        }

        try await configSvc.saveConfig(config)

        try OutputFormatter.printMessage("notes-cli initialized at ~/.notes-cli/", format: global.resolvedFormat)
    }

    // MARK: - Interactive prompts

    func promptNotesAccount(accounts: [String], defaultAccount: String?) -> String {
        let fallback = defaultAccount ?? accounts[0]
        Swift.print("Select the Apple Notes account to use:")
        for (index, account) in accounts.enumerated() {
            let suffix = account == fallback ? " (default)" : ""
            Swift.print("\(index + 1). \(account)\(suffix)")
        }
        Swift.print("Press Enter for \(fallback), or type a number:")
        Swift.print("> ", terminator: "")

        guard let line = readLine(), !line.isEmpty else {
            return fallback
        }

        guard let index = Int(line), accounts.indices.contains(index - 1) else {
            return fallback
        }

        return accounts[index - 1]
    }

    /// Resolves the Notes account selection, falling back to "iCloud" only when
    /// the database is inaccessible (e.g., no Full Disk Access in test/CI environments).
    /// Re-throws errors that indicate a genuine configuration problem (e.g., no accounts found).
    private func resolveNotesAccountSelectionWithFallback() async throws -> String {
        do {
            return try await resolveNotesAccountSelection()
        } catch let error as NotesError {
            if case .commandFailed(let msg) = error, msg.contains("Cannot access") {
                return "iCloud"
            }
            throw error
        }
    }

    /// Resolves available Notes accounts, falling back to [default] only when
    /// the database is inaccessible. Re-throws genuine configuration errors.
    private func resolveNotesAccountsWithFallback(default fallback: String) async throws -> [String] {
        do {
            return try await resolveNotesAccounts()
        } catch let error as NotesError {
            if case .commandFailed(let msg) = error, msg.contains("Cannot access") {
                return [fallback]
            }
            throw error
        }
    }

    private func resolveNotesAccounts() async throws -> [String] {
        let container = ServiceContainer.shared
        let notesSvc = try await container.notes
        let accounts = try await notesSvc.fetchAccountNames().sorted()

        guard !accounts.isEmpty else {
            throw NotesError.commandFailed(message: "No Apple Notes accounts found. Add an account in Notes before running `notes-cli init`.")
        }

        return accounts
    }

    private func resolveNotesAccountSelection() async throws -> String {
        let container = ServiceContainer.shared
        let notesSvc = try await container.notes
        let accounts = try await resolveNotesAccounts()
        return try await notesSvc.fetchDefaultAccountName() ?? accounts[0]
    }
}
