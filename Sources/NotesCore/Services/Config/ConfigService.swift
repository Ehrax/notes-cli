import Foundation

/// Loads and saves notes-cli configuration from `~/.notes-cli/config.json`.
public final class ConfigService: ConfigServiceProtocol, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - ConfigServiceProtocol

    public func loadConfig() async throws -> Config {
        let configURL = try configFilePath()
        guard fileManager.fileExists(atPath: configURL.path) else {
            Log.notice("[config] no config file found, using defaults", logger: Log.config)
            return Config.default
        }
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        Log.info("[config] loaded path=\"\(configURL.path)\"", logger: Log.config)
        return try decoder.decode(Config.self, from: data)
    }

    public func saveConfig(_ config: Config) async throws {
        _ = try notesDirectory() // ensures dir exists with 0700
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let path = try configFilePath()
        try data.write(to: path, options: .atomic)
        // Restrict config file to owner only
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    public func loadBlueprint(from path: String) async throws -> Blueprint {
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw NotesError.blueprintInvalid(reason: "File not found: \(path)")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Blueprint.self, from: data)
        } catch {
            throw NotesError.blueprintInvalid(reason: "Invalid JSON: \(error.localizedDescription)")
        }
    }

    public func applyBlueprint(_ blueprint: Blueprint, dryRun: Bool) async throws -> [String] {
        var actions: [String] = []

        // Flatten folders into creation operations
        let flatFolders = Blueprint.flattenFolders(blueprint.folders, parentPath: nil)
        var subfolderCount = 0
        for (path, folder, parent) in flatFolders {
            if parent != nil { subfolderCount += 1 }
            actions.append("Create folder: \(path)")
            if folder.isProtected == true {
                actions.append("Protect folder: \(path)")
            }
        }

        // Settings changes
        if let softDelete = blueprint.settings.softDelete {
            actions.append("Set softDelete = \(softDelete)")
        }
        if let undoHistory = blueprint.settings.undoHistory {
            actions.append("Set undoHistory = \(undoHistory)")
        }
        if let lockedNotes = blueprint.settings.lockedNotes {
            actions.append("Set lockedNotes = \(lockedNotes)")
        }

        if dryRun {
            Log.debug("[config] blueprint_dry_run folders=\(flatFolders.count) subfolders=\(subfolderCount)", logger: Log.config)
            return actions
        }

        // Apply settings to config
        var config = try await loadConfig()
        if let softDelete = blueprint.settings.softDelete {
            config.softDelete = softDelete
        }
        if let undoHistory = blueprint.settings.undoHistory {
            config.undoHistory = undoHistory
        }
        if let lockedNotes = blueprint.settings.lockedNotes {
            config.lockedNotes = lockedNotes
        }

        // Collect protected folders
        for (path, folder, _) in flatFolders where folder.isProtected == true {
            if !config.protectedFolders.contains(path) {
                config.protectedFolders.append(path)
            }
        }

        try await saveConfig(config)
        Log.info("[config] blueprint_applied folders=\(flatFolders.count) subfolders=\(subfolderCount)", logger: Log.config)

        return actions
    }

    public func notesDirectory() throws -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["NOTES_CLI_HOME"], !overridePath.isEmpty {
            let dir = URL(fileURLWithPath: overridePath, isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700,
            ])
            return dir
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".notes-cli", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700,
        ])
        return dir
    }

    public func databasePath() throws -> URL {
        let dir = try notesDirectory()
        return dir.appendingPathComponent("notes.db")
    }

    // MARK: - Private helpers

    private func configFilePath() throws -> URL {
        let dir = try notesDirectory()
        return dir.appendingPathComponent("config.json")
    }
}
