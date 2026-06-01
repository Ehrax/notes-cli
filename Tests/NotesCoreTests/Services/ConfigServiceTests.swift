import Foundation
import Testing
@testable import NotesCore

@Suite("ConfigService")
struct ConfigServiceTests {

    // MARK: - Default config

    @Test("Default config has expected values")
    func defaultConfigValues() {
        let config = Config.default
        #expect(config.protectedFolders.isEmpty)
        #expect(config.lockedNotes == true)
        #expect(config.softDelete == true)
        #expect(config.undoHistory == 50)
        #expect(config.defaultFormat == nil)
        #expect(config.notes.selectedAccount == nil)
        #expect(config.notes.rootFolder == nil)
    }

    // MARK: - Config round-trip

    @Test("Config round-trip: save then load preserves values")
    func configRoundTrip() async throws {
        let sut = ConfigService()

        var config = Config.default
        config.protectedFolders = ["Important", "Archive"]
        config.lockedNotes = false
        config.softDelete = false
        config.undoHistory = 100
        config.defaultFormat = .json
        config.notes = .init(selectedAccount: "iCloud", rootFolder: "Projects")

        try await sut.saveConfig(config)
        let loaded = try await sut.loadConfig()

        #expect(loaded.protectedFolders == ["Important", "Archive"])
        #expect(loaded.lockedNotes == false)
        #expect(loaded.softDelete == false)
        #expect(loaded.undoHistory == 100)
        #expect(loaded.defaultFormat == .json)
        #expect(loaded.notes.selectedAccount == "iCloud")
        #expect(loaded.notes.rootFolder == "Projects")

        // Restore default config to not pollute the environment
        try await sut.saveConfig(.default)
    }

    // MARK: - Blueprint parsing

    @Test("Blueprint parses from valid JSON")
    func blueprintParsesFromJSON() throws {
        let json = """
        {
            "folders": [
                {
                    "name": "Projects",
                    "icon": "folder.fill",
                    "protected": true,
                    "children": [
                        { "name": "Active" },
                        { "name": "Archive" }
                    ]
                },
                {
                    "name": "Notes"
                }
            ],
            "settings": {
                "softDelete": true,
                "undoHistory": 25,
                "lockedNotes": false
            }
        }
        """

        let data = Data(json.utf8)
        let blueprint = try JSONDecoder().decode(Blueprint.self, from: data)

        #expect(blueprint.folders.count == 2)
        #expect(blueprint.folders[0].name == "Projects")
        #expect(blueprint.folders[0].icon == "folder.fill")
        #expect(blueprint.folders[0].isProtected == true)
        #expect(blueprint.folders[0].children?.count == 2)
        #expect(blueprint.folders[0].children?[0].name == "Active")
        #expect(blueprint.folders[1].name == "Notes")
        #expect(blueprint.folders[1].isProtected == nil)

        #expect(blueprint.settings.softDelete == true)
        #expect(blueprint.settings.undoHistory == 25)
        #expect(blueprint.settings.lockedNotes == false)
    }

    @Test("Blueprint parsing fails for invalid JSON")
    func blueprintFailsForInvalidJSON() {
        let json = """
        { "folders": "not an array", "settings": {} }
        """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Blueprint.self, from: data)
        }
    }

    @Test("Blueprint parsing fails when required fields are missing")
    func blueprintFailsMissingFields() {
        let json = """
        { "settings": { "softDelete": true } }
        """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Blueprint.self, from: data)
        }
    }

    // MARK: - OutputFormat

    @Test("OutputFormat encodes and decodes correctly")
    func outputFormatRoundTrip() throws {
        let formats: [Config.OutputFormat] = [.json, .table, .markdown]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for format in formats {
            let data = try encoder.encode(format)
            let decoded = try decoder.decode(Config.OutputFormat.self, from: data)
            #expect(decoded == format)
        }
    }

    @Test("Config decoding keeps defaults for legacy files without notes scope")
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

        #expect(config.protectedFolders == ["Important"])
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
