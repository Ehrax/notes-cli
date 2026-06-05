import Foundation
import Testing
@testable import NotesCore

@Suite("ConfigService")
struct ConfigServiceTests {

    // MARK: - Default config

    @Test("Default config has expected values")
    func defaultConfigValues() {
        let config = Config.default
        #expect(config.notes.selectedAccount == nil)
        #expect(config.notes.rootFolder == nil)
    }

    // MARK: - Config round-trip

    @Test("Config round-trip: save then load preserves values")
    func configRoundTrip() async throws {
        let sut = ConfigService()

        var config = Config.default
        config.notes = .init(selectedAccount: "iCloud", rootFolder: "Projects")
        config.aiFooterEnabled = false

        try await sut.saveConfig(config)
        let loaded = try await sut.loadConfig()

        #expect(loaded.notes.selectedAccount == "iCloud")
        #expect(loaded.notes.rootFolder == "Projects")
        #expect(loaded.aiFooterEnabled == false)

        // Restore default config to not pollute the environment
        try await sut.saveConfig(.default)
    }

    @Test("Config decoding ignores legacy keys and keeps notes-scope defaults")
    func configLegacyDecodingDefaultsNotesScope() throws {
        let json = """
        {
            "protectedFolders": ["Important"],
            "lockedNotes": false,
            "softDelete": true,
            "undoHistory": 25,
            "defaultFormat": "json"
        }
        """

        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))

        #expect(config.notes.selectedAccount == nil)
        #expect(config.notes.rootFolder == nil)
    }

    @Test("Notes scope qualifies and matches folder paths")
    func notesScopeQualifiesAndMatchesFolderPaths() {
        let scope = Config.NotesScope(selectedAccount: "iCloud")

        #expect(scope.scopedFolderPath("Projects/Ideas") == "iCloud/Projects/Ideas")
        #expect(scope.scopedFolderPath("iCloud/Projects/Ideas") == "iCloud/Projects/Ideas")
        #expect(scope.resolvedFolderPath(nil) == "iCloud")
        #expect(scope.resolvedFolderPath("") == "iCloud")
        #expect(scope.matchesFolderPath("iCloud/Projects/Ideas", filter: "Projects/Ideas"))
        #expect(scope.isInSelectedAccount("iCloud/Projects/Ideas"))
        #expect(!scope.isInSelectedAccount("Gmail/Projects/Ideas"))
    }

    @Test("Notes scope uses configured root folder for default mutations")
    func notesScopeUsesConfiguredRootFolderForDefaultMutations() {
        let scope = Config.NotesScope(selectedAccount: "iCloud", rootFolder: "Projects")

        #expect(scope.resolvedFolderPath(nil) == "iCloud/Projects")
        #expect(scope.resolvedFolderPath("Ideas") == "iCloud/Ideas")
    }
}
