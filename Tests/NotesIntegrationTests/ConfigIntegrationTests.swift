import Foundation
import Testing
import NotesCore
import NotesTestSupport

// swiftlint:disable type_body_length

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
        config.protectedFolders = ["Work", "Archive"]
        config.lockedNotes = false
        config.softDelete = false
        config.undoHistory = 100
        config.defaultFormat = .json
        config.notes = .init(selectedAccount: "iCloud", rootFolder: "Projects")

        try await svc.saveConfig(config)
        let loaded = try await svc.loadConfig()

        #expect(loaded.protectedFolders == ["Work", "Archive"])
        #expect(loaded.lockedNotes == false)
        #expect(loaded.softDelete == false)
        #expect(loaded.undoHistory == 100)
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
        #expect(config.protectedFolders.isEmpty)
        #expect(config.lockedNotes == true)
        #expect(config.softDelete == true)
        #expect(config.undoHistory == 50)
        #expect(config.defaultFormat == nil)
        #expect(config.notes.selectedAccount == nil)
        #expect(config.notes.rootFolder == nil)
    }

    @Test("Legacy config file loads with default notes scope")
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
        #expect(loaded.protectedFolders == ["Work"])
        #expect(loaded.notes.selectedAccount == nil)
        #expect(loaded.notes.rootFolder == nil)
    }

    // MARK: - Blueprint load, apply, verify config updated on disk

    @Test("Blueprint apply updates config on disk")
    func blueprintApplyUpdatesConfig() async throws {
        let (svc, tempDir) = try makeIsolatedConfigService()
        defer { removeTempDirectory(tempDir) }

        // Write a blueprint JSON file
        let blueprintJSON = """
        {
            "folders": [
                { "name": "Projects", "protected": true },
                { "name": "Notes" }
            ],
            "settings": {
                "softDelete": false,
                "undoHistory": 25,
                "lockedNotes": false
            }
        }
        """
        let blueprintPath = tempDir.appendingPathComponent("blueprint.json")
        try blueprintJSON.write(to: blueprintPath, atomically: true, encoding: .utf8)

        // Load and apply blueprint
        let blueprint = try await svc.loadBlueprint(from: blueprintPath.path)
        _ = try await svc.applyBlueprint(blueprint, dryRun: false)

        // Re-load config and verify settings were applied
        let loaded = try await svc.loadConfig()
        #expect(loaded.softDelete == false)
        #expect(loaded.undoHistory == 25)
        #expect(loaded.lockedNotes == false)
        #expect(loaded.protectedFolders.contains("Projects"))
    }

    // MARK: - Blueprint dry-run does not modify disk

    @Test("Blueprint dry-run does not write config to disk")
    func blueprintDryRunNoWrite() async throws {
        let (svc, tempDir) = try makeIsolatedConfigService()
        defer { removeTempDirectory(tempDir) }

        let blueprintJSON = """
        {
            "folders": [{ "name": "DryRun" }],
            "settings": { "softDelete": false }
        }
        """
        let blueprintPath = tempDir.appendingPathComponent("blueprint.json")
        try blueprintJSON.write(to: blueprintPath, atomically: true, encoding: .utf8)

        let blueprint = try await svc.loadBlueprint(from: blueprintPath.path)
        let actions = try await svc.applyBlueprint(blueprint, dryRun: true)

        #expect(!actions.isEmpty)

        // Config should still be default (no file written)
        let loaded = try await svc.loadConfig()
        #expect(loaded.softDelete == true) // default, not overridden
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

// swiftlint:enable type_body_length
