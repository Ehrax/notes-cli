import Foundation

/// Protocol for configuration and blueprint management.
public protocol ConfigServiceProtocol: Sendable {
    /// Loads the current config from disk. Returns defaults if no config file exists.
    func loadConfig() async throws -> Config

    /// Persists the config to disk.
    func saveConfig(_ config: Config) async throws

    /// Loads a blueprint from a JSON file at the given path.
    func loadBlueprint(from path: String) async throws -> Blueprint

    /// Applies a blueprint: creates folders and updates config.
    /// If `dryRun` is true, returns planned actions without executing them.
    func applyBlueprint(_ blueprint: Blueprint, dryRun: Bool) async throws -> [String]

    /// Returns the `~/.notes-cli/` directory URL, creating it if needed.
    func notesDirectory() throws -> URL

    /// Returns the path to the database file `~/.notes-cli/notes.db`.
    func databasePath() throws -> URL
}
