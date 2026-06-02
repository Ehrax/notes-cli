import Foundation

/// Protocol for configuration management.
public protocol ConfigServiceProtocol: Sendable {
    /// Loads the current config from disk. Returns defaults if no config file exists.
    func loadConfig() async throws -> Config

    /// Persists the config to disk.
    func saveConfig(_ config: Config) async throws

    /// Returns the `~/.notes-cli/` directory URL, creating it if needed.
    func notesDirectory() throws -> URL
}
