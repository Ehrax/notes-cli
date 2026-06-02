import Foundation
import Testing
import NotesCore
import NotesTestSupport

/// A FileManager subclass that overrides the home directory for isolated config tests.
final class IsolatedFileManager: FileManager, @unchecked Sendable {
    let isolatedHome: URL

    init(home: URL) {
        self.isolatedHome = home
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL { isolatedHome }
}

@Suite("Config Integration Tests")
struct ConfigIntegrationTests {

    private func makeIsolatedConfigService() throws -> (ConfigService, URL) {
        let tempDir = try makeTempDirectory()
        let fm = IsolatedFileManager(home: tempDir)
        let svc = ConfigService(fileManager: fm)
        return (svc, tempDir)
    }

    // MARK: - Save and load round-trip

    @Test("Save and load config round-trip with custom values")
    func saveAndLoadRoundTrip() async throws {
        let (svc, tempDir) = try makeIsolatedConfigService()
        defer { removeTempDirectory(tempDir) }

        var config = Config.default
        config.defaultFormat = .json
        config.notes = .init(selectedAccount: "iCloud", rootFolder: "Projects")

        try await svc.saveConfig(config)
        let loaded = try await svc.loadConfig()

        #expect(loaded.defaultFormat == .json)
        #expect(loaded.notes.selectedAccount == "iCloud")
        #expect(loaded.notes.rootFolder == "Projects")
    }

    // MARK: - Default config when no file exists

    @Test("Default config returned when no config file exists")
    func defaultConfigWhenNoFile() async throws {
        let (svc, tempDir) = try makeIsolatedConfigService()
        defer { removeTempDirectory(tempDir) }

        let config = try await svc.loadConfig()
        #expect(config.defaultFormat == nil)
        #expect(config.notes.selectedAccount == nil)
        #expect(config.notes.rootFolder == nil)
    }

    @Test("Legacy config file loads, ignoring removed keys")
    func legacyConfigFileLoadsWithDefaultNotesScope() async throws {
        let (svc, tempDir) = try makeIsolatedConfigService()
        defer { removeTempDirectory(tempDir) }

        let legacyJSON = """
        {
            "protectedFolders": ["Work"],
            "lockedNotes": false,
            "softDelete": true,
            "undoHistory": 10
        }
        """
        let configPath = try svc.notesDirectory().appendingPathComponent("config.json")
        try legacyJSON.write(to: configPath, atomically: true, encoding: .utf8)

        let loaded = try await svc.loadConfig()
        #expect(loaded.notes.selectedAccount == nil)
        #expect(loaded.notes.rootFolder == nil)
    }

    // MARK: - Directory and file permissions

    @Test("NotesCLI directory has 0700 and config file has 0600 permissions")
    func directoryAndFilePermissions() async throws {
        let (svc, tempDir) = try makeIsolatedConfigService()
        defer { removeTempDirectory(tempDir) }

        // Create directory by saving config
        try await svc.saveConfig(.default)

        let notesDir = try svc.notesDirectory()
        let configFile = notesDir.appendingPathComponent("config.json")

        let fm = FileManager.default

        // Check directory permissions (0700 = owner rwx)
        let dirAttrs = try fm.attributesOfItem(atPath: notesDir.path)
        if let dirPerms = dirAttrs[.posixPermissions] as? Int {
            #expect(dirPerms == 0o700)
        }

        // Check file permissions (0600 = owner rw)
        let fileAttrs = try fm.attributesOfItem(atPath: configFile.path)
        if let filePerms = fileAttrs[.posixPermissions] as? Int {
            #expect(filePerms == 0o600)
        }
    }
}
