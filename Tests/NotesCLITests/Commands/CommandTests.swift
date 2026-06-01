import ArgumentParser
import Darwin
import Foundation
import Testing
@testable import NotesCLI
@testable import NotesCore
import NotesTestSupport

private actor AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            let continuation = waiters.removeFirst()
            continuation.resume()
        }
    }
}

private let containerTestLock = AsyncLock()
private let stdoutTestLock = AsyncLock()

private func discardStdout(_ body: @escaping @Sendable () async throws -> Void) async throws {
    try await stdoutTestLock.withLock {
        fflush(stdout)
        let pipe = Pipe()
        let saved = dup(STDOUT_FILENO)
        setvbuf(stdout, nil, _IONBF, 0)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        do {
            try await body()
        } catch {
            fflush(stdout)
            pipe.fileHandleForWriting.closeFile()
            dup2(saved, STDOUT_FILENO)
            close(saved)
            throw error
        }

        fflush(stdout)
        pipe.fileHandleForWriting.closeFile()
        dup2(saved, STDOUT_FILENO)
        close(saved)
        _ = pipe.fileHandleForReading.readDataToEndOfFile()
    }
}

private func captureStdout(_ body: @escaping @Sendable () async throws -> Void) async throws -> String {
    try await stdoutTestLock.withLock {
        fflush(stdout)
        let pipe = Pipe()
        let saved = dup(STDOUT_FILENO)
        setvbuf(stdout, nil, _IONBF, 0)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        do {
            try await body()
        } catch {
            fflush(stdout)
            pipe.fileHandleForWriting.closeFile()
            dup2(saved, STDOUT_FILENO)
            close(saved)
            throw error
        }

        fflush(stdout)
        pipe.fileHandleForWriting.closeFile()
        dup2(saved, STDOUT_FILENO)
        close(saved)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

@Suite("Command Structure Tests")
struct CommandTests {
    @Test("RootCommand has expected subcommands registered")
    func notesCLISubcommands() {
        let subcommandNames = RootCommand.configuration.subcommands.map {
            $0.configuration.commandName ?? ""
        }

        #expect(subcommandNames.contains("init"))
        #expect(subcommandNames.contains("sync"))
        #expect(subcommandNames.contains("status"))
        #expect(subcommandNames.contains("notes"))
        #expect(subcommandNames.contains("undo"))
        #expect(subcommandNames.contains("history"))
        #expect(subcommandNames.contains("link"))
        #expect(subcommandNames.contains("tag"))
        #expect(subcommandNames.contains("tags"))
        #expect(subcommandNames.contains("links"))
    }

    @Test("NotesCommand has expected subcommands")
    func notesSubcommands() {
        let subcommandNames = NotesCommand.configuration.subcommands.map {
            $0.configuration.commandName ?? ""
        }

        #expect(subcommandNames.contains("list"))
        #expect(subcommandNames.contains("read"))
        #expect(subcommandNames.contains("create"))
        #expect(subcommandNames.contains("edit"))
        #expect(subcommandNames.contains("delete"))
        #expect(subcommandNames.contains("move"))
        #expect(subcommandNames.contains("search"))
    }

    @Test("OutputFormat cases are complete")
    func outputFormatCases() {
        let allCases = OutputFormat.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.json))
        #expect(allCases.contains(.table))
        #expect(allCases.contains(.markdown))
    }

    @Test("OutputFormat is expressible by argument")
    func outputFormatFromArgument() {
        #expect(OutputFormat(argument: "json") == .json)
        #expect(OutputFormat(argument: "table") == .table)
        #expect(OutputFormat(argument: "markdown") == .markdown)
        #expect(OutputFormat(argument: "invalid") == nil)
    }

    @Test("RootCommand version matches NotesCore")
    func versionMatch() {
        #expect(RootCommand.configuration.version == NotesCore.version)
    }

    @Test("SyncCommand supports explicit full sync flag")
    func syncCommandFullFlag() throws {
        let command = try SyncCommand.parse(["--full"])
        #expect(command.full)
    }
}

@Suite("Command Mutation Sync Tests", .serialized)
struct CommandMutationSyncTests {
    private func withOverrides(
        notes: MockNotesService = MockNotesService(),
        db: MockDatabaseService = MockDatabaseService(),
        config: Config = .default,
        _ body: @escaping @Sendable (MockNotesService, MockDatabaseService) async throws -> Void
    ) async throws {
        try await containerTestLock.withLock {
            let container = ServiceContainer.shared
            let safety = SafetyService(configProvider: { config }, db: db, notes: notes)
            await container.override(notes: notes)
            await container.override(database: db)
            await container.override(safety: safety)
            do {
                try await body(notes, db)
                await container.reset()
            } catch {
                await container.reset()
                throw error
            }
        }
    }

    @Test("notes create updates the local database")
    func notesCreateUpdatesDatabase() async throws {
        try await withOverrides { _, db in
            let command = try NotesCreateCommand.parse([
                "--folder", "Projects/Ideas",
                "--title", "Fresh Note",
                "--body", "<p>Hello</p>",
                "--format", "json",
            ])

            try await discardStdout {
                try await command.run()
            }

            let notes = try await db.fetchAllNotes()
            #expect(notes.count == 1)
            #expect(notes[0].title == "Fresh Note")
            #expect(notes[0].folderPath == "Projects/Ideas")
        }
    }

    @Test("notes create scopes unqualified folder to selected account")
    func notesCreateScopesUnqualifiedFolderToSelectedAccount() async throws {
        let notesService = MockNotesService()
        notesService.scopedAccountName = "iCloud"

        try await withOverrides(notes: notesService, config: Config(notes: .init(selectedAccount: "iCloud"))) { notes, db in
            let command = try NotesCreateCommand.parse([
                "--folder", "Projects/Ideas",
                "--title", "Scoped Note",
                "--body", "<p>Hello</p>",
                "--format", "json",
            ])

            try await discardStdout {
                try await command.run()
            }

            let storedNotes = try await db.fetchAllNotes()
            #expect(notes.lastCreatedFolder == "iCloud/Projects/Ideas")
            #expect(storedNotes.count == 1)
            #expect(storedNotes[0].folderPath == "iCloud/Projects/Ideas")
        }
    }

    @Test("notes create preserves qualified folder in selected account")
    func notesCreatePreservesQualifiedFolderInSelectedAccount() async throws {
        let notesService = MockNotesService()
        notesService.scopedAccountName = "iCloud"

        try await withOverrides(notes: notesService, config: Config(notes: .init(selectedAccount: "iCloud"))) { notes, db in
            let command = try NotesCreateCommand.parse([
                "--folder", "iCloud/Projects/Ideas",
                "--title", "Qualified Note",
                "--body", "<p>Hello</p>",
                "--format", "json",
            ])

            try await discardStdout {
                try await command.run()
            }

            let storedNotes = try await db.fetchAllNotes()
            #expect(notes.lastCreatedFolder == "iCloud/Projects/Ideas")
            #expect(storedNotes.count == 1)
            #expect(storedNotes[0].folderPath == "iCloud/Projects/Ideas")
        }
    }

    @Test("notes create without folder targets scoped account root")
    func notesCreateWithoutFolderTargetsScopedAccountRoot() async throws {
        let notesService = MockNotesService()
        notesService.scopedAccountName = "iCloud"

        try await withOverrides(notes: notesService, config: Config(notes: .init(selectedAccount: "iCloud"))) { notes, db in
            let command = try NotesCreateCommand.parse([
                "--title", "Root Note",
                "--body", "<p>Hello</p>",
                "--format", "json",
            ])

            try await discardStdout {
                try await command.run()
            }

            let storedNotes = try await db.fetchAllNotes()
            #expect(notes.lastCreatedFolder == "iCloud")
            #expect(storedNotes.count == 1)
            #expect(storedNotes[0].folderPath == "iCloud")
        }
    }

    @Test("notes edit refreshes the local database")
    func notesEditRefreshesDatabase() async throws {
        let notesService = MockNotesService()
        notesService.notes = [makeSampleAppleNote(id: "n1", name: "Original", folder: "Notes")]
        let db = MockDatabaseService()
        try await db.insertNote(makeSampleNote(id: "n1", title: "Original", bodyPlaintext: "Old"))

        try await withOverrides(notes: notesService, db: db) { _, db in
            let command = try NotesEditCommand.parse([
                "n1",
                "--title", "Updated",
                "--body", "<p>New</p>",
                "--format", "json",
            ])

            try await discardStdout {
                try await command.run()
            }

            let note = try await db.fetchNote(id: "n1")
            #expect(note?.title == "Updated")
            #expect(note?.bodyPlaintext == "Hello")
        }
    }

    @Test("notes move refreshes the local database folder path")
    func notesMoveRefreshesDatabase() async throws {
        let notesService = MockNotesService()
        notesService.notes = [makeSampleAppleNote(id: "n1", name: "Original", folder: "Notes")]
        let db = MockDatabaseService()
        try await db.insertNote(makeSampleNote(id: "n1", title: "Original", bodyPlaintext: "Body"))

        try await withOverrides(notes: notesService, db: db) { _, db in
            let command = try NotesMoveCommand.parse([
                "n1",
                "--to", "Projects/Archive",
                "--format", "json",
            ])

            try await discardStdout {
                try await command.run()
            }

            let note = try await db.fetchNote(id: "n1")
            #expect(note?.folderPath == "Projects/Archive")
        }
    }

    @Test("notes move stores scoped destination in database and history")
    func notesMoveStoresScopedDestinationInDatabaseAndHistory() async throws {
        let notesService = MockNotesService()
        notesService.scopedAccountName = "iCloud"
        notesService.notes = [
            makeSampleAppleNote(id: "n1", name: "Original", folder: "iCloud/Notes"),
        ]
        let db = MockDatabaseService()
        try await db.insertNote(
            makeSampleNote(id: "n1", title: "Original", bodyPlaintext: "Body", folderPath: "iCloud/Notes")
        )

        try await withOverrides(notes: notesService, db: db, config: Config(notes: .init(selectedAccount: "iCloud"))) { notes, db in
            let command = try NotesMoveCommand.parse([
                "n1",
                "--to", "Projects/Archive",
                "--format", "json",
            ])

            try await discardStdout {
                try await command.run()
            }

            let note = try await db.fetchNote(id: "n1")
            #expect(notes.lastMovedFolder == "iCloud/Projects/Archive")
            #expect(note?.folderPath == "iCloud/Projects/Archive")

            let action = try #require(db.actionRecords.last)
            let afterJSON = try #require(action.afterState)
            let afterCheckpoint = try ActionLogger.decodeCheckpoint(from: afterJSON)
            #expect(afterCheckpoint.folderPath == "iCloud/Projects/Archive")
        }
    }

    @Test("notes create records action only after database sync succeeds")
    func notesCreateRecordsActionAfterDatabaseSync() async throws {
        let notesService = MockNotesService()
        let db = MockDatabaseService()
        db.failAllNoteInserts = true

        await #expect(throws: NotesError.self) {
            try await withOverrides(notes: notesService, db: db) { _, _ in
                let command = try NotesCreateCommand.parse([
                    "--folder", "Projects/Ideas",
                    "--title", "Fresh Note",
                    "--body", "<p>Hello</p>",
                    "--format", "json",
                ])

                try await discardStdout {
                    try await command.run()
                }
            }
        }

        #expect(db.actionRecords.isEmpty)
        #expect(notesService.createNoteCalled == true)
    }

    @Test("mutation refresh inserts fallback note when local row is missing")
    func noteMutationSyncInsertsFallbackWhenLocalRowMissing() async throws {
        let notesService = MockNotesService()
        notesService.fetchNoteSequence = [nil]
        let db = MockDatabaseService()
        db.strictMissingNoteUpdates = true
        let fallback = makeSampleNote(
            id: "n1",
            title: "Recovered",
            bodyPlaintext: "Recovered",
            folderPath: "Projects/Archive"
        )

        let refreshedNote = try await NoteMutationSync.refreshExistingNote(
            id: "n1",
            fallback: fallback,
            notes: notesService,
            db: db
        )

        #expect(refreshedNote.title == "Recovered")
        #expect(refreshedNote.folderPath == "Projects/Archive")
        let persistedNote = try await db.fetchNote(id: "n1")
        #expect(persistedNote?.folderPath == "Projects/Archive")
    }
}

@Suite("Command Read Tests", .serialized)
struct CommandReadTests {
    private func withOverrides(
        db: MockDatabaseService,
        config: InitCommandConfigService,
        _ body: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await containerTestLock.withLock {
            let container = ServiceContainer.shared
            await container.reset()
            await container.override(database: db)
            await container.override(config: config)
            do {
                try await body()
                await container.reset()
            } catch {
                await container.reset()
                throw error
            }
        }
    }

    @Test("notes list matches unqualified folder filter against scoped paths")
    func notesListMatchesUnqualifiedFolderFilter() async throws {
        let db = MockDatabaseService()
        try await db.insertNote(makeSampleNote(id: "n1", title: "Scoped", bodyPlaintext: "One", folderPath: "iCloud/Projects/Ideas"))
        try await db.insertNote(makeSampleNote(id: "n2", title: "Other", bodyPlaintext: "Two", folderPath: "iCloud/Archive"))

        let config = try InitCommandConfigService()
        config.loadedConfig = Config(notes: .init(selectedAccount: "iCloud"))

        try await withOverrides(db: db, config: config) {
            let command = try NotesListCommand.parse(["--folder", "Projects/Ideas", "--format", "json"])
            let output = try await captureStdout {
                try await command.run()
            }

            #expect(output.contains("Scoped"))
            #expect(!output.contains("Other"))
        }
    }

    @Test("notes search matches unqualified folder filter against scoped paths")
    func notesSearchMatchesUnqualifiedFolderFilter() async throws {
        let db = MockDatabaseService()
        try await db.insertNote(makeSampleNote(id: "n1", title: "Scoped Search", bodyPlaintext: "Hello", folderPath: "iCloud/Projects/Ideas"))
        try await db.insertNote(makeSampleNote(id: "n2", title: "Wrong Folder", bodyPlaintext: "Hello", folderPath: "iCloud/Archive"))

        let config = try InitCommandConfigService()
        config.loadedConfig = Config(notes: .init(selectedAccount: "iCloud"))

        try await withOverrides(db: db, config: config) {
            let command = try NotesSearchCommand.parse(["Hello", "--folder", "Projects/Ideas", "--format", "json"])
            let output = try await captureStdout {
                try await command.run()
            }

            #expect(output.contains("Scoped Search"))
            #expect(!output.contains("Wrong Folder"))
        }
    }
}

@Suite("Init Command Tests", .serialized)
struct InitCommandTests {
    private func withOverrides(
        notes: MockNotesService,
        config: InitCommandConfigService,
        _ body: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await containerTestLock.withLock {
            let container = ServiceContainer.shared
            await container.reset()
            await container.override(notes: notes)
            await container.override(config: config)
            do {
                try await body()
                await container.reset()
            } catch {
                await container.reset()
                throw error
            }
        }
    }

    @Test("init --yes persists the default Notes account")
    func initYesPersistsDefaultNotesAccount() async throws {
        let notes = MockNotesService()
        notes.accountNames = ["Gmail", "iCloud"]
        notes.defaultAccountName = "iCloud"
        let config = try InitCommandConfigService()

        try await withOverrides(notes: notes, config: config) {
            let command = try InitCommand.parse(["--yes", "--format", "json"])
            try await discardStdout {
                try await command.run()
            }
        }

        #expect(config.savedConfig?.notes.selectedAccount == "iCloud")
        #expect(notes.fetchAccountNamesCalled)
        #expect(notes.fetchDefaultAccountNameCalled)
    }

    @Test("init fails clearly when Notes has no accounts")
    func initFailsWhenNoNotesAccountsAreAvailable() async throws {
        let notes = MockNotesService()
        notes.accountNames = []
        let config = try InitCommandConfigService()

        do {
            try await withOverrides(notes: notes, config: config) {
                let command = try InitCommand.parse(["--yes", "--format", "json"])
                try await discardStdout {
                    try await command.run()
                }
            }
            Issue.record("Expected init to fail when no Apple Notes accounts are available")
        } catch let error as NotesError {
            #expect(error.errorDescription?.contains("No Apple Notes accounts found") == true)
        }

        #expect(config.savedConfig == nil)
    }

    @Test("ServiceContainer builds Notes service with configured account scope")
    func serviceContainerBuildsNotesServiceWithConfiguredAccountScope() async throws {
        try await containerTestLock.withLock {
            let container = ServiceContainer.shared
            let config = try InitCommandConfigService()
            config.loadedConfig = Config(notes: .init(selectedAccount: "iCloud", rootFolder: nil))

            await container.reset()
            await container.override(config: config)
            let notes = try await container.notes
            await container.reset()

            let directNotes = try #require(notes as? DirectNotesService)
            #expect(directNotes.scope.selectedAccount == "iCloud")
        }
    }

    @Test("init --from persists selected Notes account before applying blueprint")
    func initFromBlueprintPersistsSelectedNotesAccount() async throws {
        let notes = MockNotesService()
        notes.accountNames = ["Gmail", "iCloud"]
        notes.defaultAccountName = "iCloud"
        let config = try InitCommandConfigService()
        let blueprintPath = config.rootDirectory.appendingPathComponent("blueprint.json")
        try "{\"folders\":[{\"name\":\"Projects\"}],\"settings\":{}}".write(
            to: blueprintPath,
            atomically: true,
            encoding: .utf8
        )

        try await withOverrides(notes: notes, config: config) {
            let command = try InitCommand.parse(["--from", blueprintPath.path, "--format", "json"])
            try await discardStdout {
                try await command.run()
            }
        }

        #expect(config.savedConfig?.notes.selectedAccount == "iCloud")
        #expect(config.appliedBlueprints.count == 1)
    }
}

final class InitCommandConfigService: ConfigServiceProtocol, @unchecked Sendable {
    let rootDirectory: URL
    var loadedConfig: Config = .default
    var savedConfig: Config?
    var appliedBlueprints: [Blueprint] = []

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-cli-init-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func loadConfig() async throws -> Config {
        loadedConfig
    }

    func saveConfig(_ config: Config) async throws {
        loadedConfig = config
        savedConfig = config
    }

    func loadBlueprint(from path: String) async throws -> Blueprint {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(Blueprint.self, from: data)
    }

    func applyBlueprint(_ blueprint: Blueprint, dryRun: Bool) async throws -> [String] {
        appliedBlueprints.append(blueprint)
        return []
    }

    func notesDirectory() throws -> URL {
        rootDirectory
    }

    func databasePath() throws -> URL {
        rootDirectory.appendingPathComponent("notes.db")
    }
}
