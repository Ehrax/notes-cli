import ArgumentParser
import NotesCore
import Foundation

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize notes-cli: create ~/.notes-cli/, config, database, and Apple Notes folders"
    )

    @OptionGroup var global: GlobalOptions

    @Option(name: .long, help: "Path to a blueprint JSON file to apply")
    var from: String?

    @Flag(name: .long, help: "Preview changes without applying them")
    var dryRun = false

    @Flag(name: .long, help: "Non-interactive mode, accept all defaults (for AI agents)")
    var yes = false

    func run() async throws {
        global.configureLogging()
        let container = ServiceContainer.shared
        let configSvc = try await container.config

        if let blueprintPath = from {
            try await initFromBlueprint(configSvc: configSvc, path: blueprintPath)
        } else {
            try await initDefault(configSvc: configSvc)
        }
    }

    private func initFromBlueprint(configSvc: any ConfigServiceProtocol, path: String) async throws {
        let selectedAccount = try await resolveNotesAccountSelectionWithFallback()
        var config = try await configSvc.loadConfig()
        let needsAccountSelection = config.notes.selectedAccount == nil
        if needsAccountSelection {
            config.notes.selectedAccount = selectedAccount
            if !dryRun {
                try await configSvc.saveConfig(config)
            }
        }

        let blueprint = try await configSvc.loadBlueprint(from: path)
        var actions = try await configSvc.applyBlueprint(blueprint, dryRun: dryRun)
        if dryRun, needsAccountSelection {
            actions.insert("Set notes.selectedAccount = \(selectedAccount)", at: 0)
        }

        if dryRun {
            try OutputFormatter.printMessage("Dry run - planned actions:", format: global.resolvedFormat)
            try OutputFormatter.printStringList(actions, format: global.resolvedFormat)
        } else {
            try OutputFormatter.printMessage(
                "Initialized notes-cli from blueprint (\(actions.count) actions applied).",
                format: global.resolvedFormat
            )
            try OutputFormatter.printStringList(actions, format: global.resolvedFormat)
        }
    }

    private func initDefault(configSvc: any ConfigServiceProtocol) async throws {
        // Ensure ~/.notes-cli/ directory and config exist
        _ = try configSvc.notesDirectory()
        let defaultAccount = try await resolveNotesAccountSelectionWithFallback()
        let accounts = try await resolveNotesAccountsWithFallback(default: defaultAccount)

        var config: Config
        if yes {
            config = Config.default
            config.notes.selectedAccount = defaultAccount
        } else {
            // Interactive wizard
            config = Config.default
            config.notes.selectedAccount = promptNotesAccount(accounts: accounts, defaultAccount: defaultAccount)
            config.protectedFolders = promptProtectedFolders()
            config.softDelete = promptYesNo("Enable soft-delete (archive instead of permanent delete)?", defaultValue: true)
            config.lockedNotes = promptYesNo("Guard locked notes from modification?", defaultValue: true)
        }

        try await configSvc.saveConfig(config)

        // Initialize the database by instantiating DatabaseService
        let dbPath = try configSvc.databasePath()
        _ = try DatabaseService(path: dbPath.path)

        try OutputFormatter.printMessage("notes-cli initialized at ~/.notes-cli/", format: global.resolvedFormat)
    }

    // MARK: - Interactive prompts

    private func promptProtectedFolders() -> [String] {
        Swift.print("Enter protected folder names (comma-separated, or press Enter to skip):")
        Swift.print("> ", terminator: "")
        guard let line = readLine(), !line.isEmpty else { return [] }
        return line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func promptYesNo(_ question: String, defaultValue: Bool) -> Bool {
        let defaultHint = defaultValue ? "Y/n" : "y/N"
        Swift.print("\(question) [\(defaultHint)]:")
        Swift.print("> ", terminator: "")
        guard let line = readLine(), !line.isEmpty else { return defaultValue }
        return line.lowercased().hasPrefix("y")
    }

    func promptNotesAccount(accounts: [String], defaultAccount: String?) -> String {
        let fallback = defaultAccount ?? accounts[0]
        Swift.print("Select the Apple Notes account to sync:")
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
            if case .commandFailed(let msg) = error,
               msg.contains("NoteStore cache not found") || msg.contains("Cannot access") || msg.contains("Failed to copy") {
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
            if case .commandFailed(let msg) = error,
               msg.contains("NoteStore cache not found") || msg.contains("Cannot access") || msg.contains("Failed to copy") {
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
