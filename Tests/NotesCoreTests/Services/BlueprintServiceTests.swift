import Foundation
import Testing
@testable import NotesCore
import NotesTestSupport

@Suite("BlueprintService")
struct BlueprintServiceTests {

    // MARK: - Helpers

    private func makeSUT() -> (BlueprintService, MockConfigService, MockNotesService) {
        let configService = MockConfigService()
        let notes = MockNotesService()
        let sut = BlueprintService(configService: configService, notes: notes)
        return (sut, configService, notes)
    }

    private func sampleBlueprint() -> Blueprint {
        Blueprint(
            folders: [
                .init(name: "Projects", icon: "folder.fill", children: [
                    .init(name: "Active"),
                    .init(name: "Archive", isProtected: true),
                ], isProtected: true),
                .init(name: "Notes"),
            ],
            settings: .init(softDelete: true, undoHistory: 25)
        )
    }

    // MARK: - Dry run

    @Test("Dry run returns planned actions without executing")
    func dryRunReturnsPlannedActions() async throws {
        let (sut, configService, notes) = makeSUT()
        let blueprint = sampleBlueprint()

        let actions = try await sut.apply(blueprint, dryRun: true)

        #expect(actions.contains { $0.contains("Projects") })
        #expect(actions.contains { $0.contains("Notes") })
        // Dry run should not create folders in notes
        #expect(notes.createFolderCalled == false)
        // Dry run should not save config
        #expect(configService.savedConfig == nil)
    }

    // MARK: - Folder flattening

    @Test("Folder flattening produces correct paths from nested structure")
    func folderFlatteningProducesCorrectPaths() {
        let blueprint = sampleBlueprint()

        let flattened = Blueprint.flattenFolders(blueprint.folders, parentPath: nil)
        let paths = flattened.map(\.path)

        #expect(paths.contains("Projects"))
        #expect(paths.contains("Projects/Active"))
        #expect(paths.contains("Projects/Archive"))
        #expect(paths.contains("Notes"))
        #expect(flattened.count == 4)
    }

    @Test("Folder flattening with parent path prepends prefix")
    func folderFlatteningWithParentPath() {
        let folders: [Blueprint.BlueprintFolder] = [
            .init(name: "Sub", children: [.init(name: "Deep")]),
        ]

        let flattened = Blueprint.flattenFolders(folders, parentPath: "Root")
        let paths = flattened.map(\.path)

        #expect(paths == ["Root/Sub", "Root/Sub/Deep"])
    }

    // MARK: - Validation

    @Test("Validation catches empty folder names")
    func validationCatchesEmptyFolderNames() {
        let (sut, _, _) = makeSUT()
        let blueprint = Blueprint(
            folders: [.init(name: "   ")],
            settings: .init()
        )

        let errors = sut.validate(blueprint)
        #expect(!errors.isEmpty)
        #expect(errors.first?.contains("must not be empty") == true)
    }

    @Test("Validation catches empty folders list")
    func validationCatchesEmptyFoldersList() {
        let (sut, _, _) = makeSUT()
        let blueprint = Blueprint(folders: [], settings: .init())

        let errors = sut.validate(blueprint)
        #expect(errors.contains { $0.contains("at least one folder") })
    }

    @Test("Valid blueprint passes validation")
    func validBlueprintPassesValidation() {
        let (sut, _, _) = makeSUT()
        let blueprint = sampleBlueprint()

        let errors = sut.validate(blueprint)
        #expect(errors.isEmpty)
    }

    // MARK: - Apply

    @Test("Apply creates folders and saves config")
    func applyCreatesFoldersAndSavesConfig() async throws {
        let (sut, configService, notes) = makeSUT()
        let blueprint = sampleBlueprint()

        let actions = try await sut.apply(blueprint, dryRun: false)

        #expect(!actions.isEmpty)
        #expect(notes.createFolderCalled == true)
        #expect(configService.savedConfig != nil)
    }
}

// MARK: - MockConfigService

/// Minimal mock for ConfigServiceProtocol used in BlueprintService tests.
final class MockConfigService: ConfigServiceProtocol, @unchecked Sendable {
    var config: Config = .default
    var savedConfig: Config?
    var blueprintActions: [String] = []

    func loadConfig() async throws -> Config { config }

    func saveConfig(_ config: Config) async throws {
        self.config = config
        self.savedConfig = config
    }

    func loadBlueprint(from path: String) async throws -> Blueprint {
        throw NotesError.blueprintInvalid(reason: "Mock: loadBlueprint not implemented")
    }

    func applyBlueprint(_ blueprint: Blueprint, dryRun: Bool) async throws -> [String] {
        // Simulate what ConfigService.applyBlueprint does
        var actions: [String] = []
        func flatten(_ folders: [Blueprint.BlueprintFolder], parent: String?) {
            for folder in folders {
                let path = parent.map { "\($0)/\(folder.name)" } ?? folder.name
                actions.append("Create folder: \(path)")
                if folder.isProtected == true {
                    actions.append("Protect folder: \(path)")
                }
                if let children = folder.children {
                    flatten(children, parent: path)
                }
            }
        }
        flatten(blueprint.folders, parent: nil)

        if let sd = blueprint.settings.softDelete { actions.append("Set softDelete = \(sd)") }
        if let uh = blueprint.settings.undoHistory { actions.append("Set undoHistory = \(uh)") }
        if let ln = blueprint.settings.lockedNotes { actions.append("Set lockedNotes = \(ln)") }

        if !dryRun {
            var cfg = config
            if let sd = blueprint.settings.softDelete { cfg.softDelete = sd }
            if let uh = blueprint.settings.undoHistory { cfg.undoHistory = uh }
            if let ln = blueprint.settings.lockedNotes { cfg.lockedNotes = ln }
            for folder in blueprint.folders {
                if folder.isProtected == true && !cfg.protectedFolders.contains(folder.name) {
                    cfg.protectedFolders.append(folder.name)
                }
            }
            try await saveConfig(cfg)
        }

        return actions
    }

    func notesDirectory() throws -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notes-cli", isDirectory: true)
    }

    func databasePath() throws -> URL {
        try notesDirectory().appendingPathComponent("notes.db")
    }
}
