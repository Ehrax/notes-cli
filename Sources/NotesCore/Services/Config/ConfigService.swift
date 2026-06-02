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

    // MARK: - Private helpers

    private func configFilePath() throws -> URL {
        let dir = try notesDirectory()
        return dir.appendingPathComponent("config.json")
    }
}
