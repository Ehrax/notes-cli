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
        #expect(subcommandNames.contains("notes"))
        #expect(subcommandNames.contains("folders"))
        #expect(subcommandNames.contains("folder"))
        #expect(subcommandNames.contains("export"))
    }

    @Test("FolderCommand has expected subcommands")
    func folderSubcommands() {
        let subcommandNames = FolderCommand.configuration.subcommands.map {
            $0.configuration.commandName ?? ""
        }

        #expect(subcommandNames.contains("create"))
        #expect(subcommandNames.contains("rename"))
        #expect(subcommandNames.contains("move"))
        #expect(subcommandNames.contains("delete"))
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
}

@Suite("Command Write Tests", .serialized)
struct CommandWriteTests {
    private func withNotes(
        _ notes: MockNotesService,
        _ body: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await containerTestLock.withLock {
            let container = ServiceContainer.shared
            await container.reset()
            await container.override(notes: notes)
            do {
                try await body()
                await container.reset()
            } catch {
                await container.reset()
                throw error
            }
        }
    }

    @Test("create calls the writer with title, body, and folder")
    func createCallsWriter() async throws {
        let notes = MockNotesService()
        try await withNotes(notes) {
            let command = try NotesCreateCommand.parse([
                "--folder", "Projects/Ideas", "--title", "Fresh", "--body", "<p>hi</p>", "--format", "json",
            ])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.createNoteCalled)
        #expect(notes.lastCreatedTitle == "Fresh")
        #expect(notes.lastCreatedBody == "<p>hi</p>")
        #expect(notes.lastCreatedFolder == "Projects/Ideas")
    }

    @Test("edit calls the writer with the provided title and body")
    func editCallsWriter() async throws {
        let notes = MockNotesService()
        notes.notes = [makeSampleAppleNote(id: "n1", name: "Old", folder: "Notes")]
        try await withNotes(notes) {
            let command = try NotesEditCommand.parse([
                "n1", "--title", "New", "--body", "<p>new</p>", "--format", "json",
            ])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.updateNoteCalled)
        #expect(notes.lastUpdatedID == "n1")
        #expect(notes.lastUpdatedTitle == "New")
        #expect(notes.lastUpdatedBody == "<p>new</p>")
    }

    @Test("move calls the writer with the destination folder")
    func moveCallsWriter() async throws {
        let notes = MockNotesService()
        notes.notes = [makeSampleAppleNote(id: "n1", name: "N", folder: "Notes")]
        try await withNotes(notes) {
            let command = try NotesMoveCommand.parse(["n1", "--folder", "Archive", "--format", "json"])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.moveNoteCalled)
        #expect(notes.lastMovedID == "n1")
        #expect(notes.lastMovedFolder == "Archive")
    }

    @Test("delete really deletes (not soft-delete)")
    func deleteCallsWriter() async throws {
        let notes = MockNotesService()
        notes.notes = [makeSampleAppleNote(id: "n1", name: "N", folder: "Notes")]
        try await withNotes(notes) {
            let command = try NotesDeleteCommand.parse(["n1", "--format", "json"])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.deleteNoteCalled)
        #expect(notes.lastDeletedID == "n1")
    }
}

@Suite("Folder Command Tests", .serialized)
struct FolderCommandTests {
    private func withNotes(
        _ notes: MockNotesService,
        _ body: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await containerTestLock.withLock {
            let container = ServiceContainer.shared
            await container.reset()
            await container.override(notes: notes)
            do {
                try await body()
                await container.reset()
            } catch {
                await container.reset()
                throw error
            }
        }
    }

    @Test("folders lists folders from the notes service")
    func foldersListsFolders() async throws {
        let notes = MockNotesService()
        notes.folders = [
            AppleFolderRaw(id: "f1", name: "Projects", path: "Projects", parentPath: nil),
            AppleFolderRaw(id: "f2", name: "Ideas", path: "Projects/Ideas", parentPath: "Projects"),
        ]
        let output = try await captureStdout {
            try await withNotes(notes) {
                let command = try FoldersCommand.parse(["--format", "json"])
                try await command.run()
            }
        }
        #expect(notes.fetchFoldersCalled)
        #expect(output.contains("Projects"))
        #expect(output.contains("Ideas"))
    }

    @Test("folder create calls the writer with name and parent")
    func folderCreateCallsWriter() async throws {
        let notes = MockNotesService()
        try await withNotes(notes) {
            let command = try FolderCreateCommand.parse(["Ideas", "--parent", "Projects", "--format", "json"])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.createFolderCalled)
        #expect(notes.lastCreatedFolderName == "Ideas")
        #expect(notes.lastCreatedFolderParent == "Projects")
    }

    @Test("folder rename calls the writer with path and new name")
    func folderRenameCallsWriter() async throws {
        let notes = MockNotesService()
        try await withNotes(notes) {
            let command = try FolderRenameCommand.parse(["Projects", "Work", "--format", "json"])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.renameFolderCalled)
        #expect(notes.lastRenamedFolderPath == "Projects")
        #expect(notes.lastRenamedFolderNewName == "Work")
    }

    @Test("folder move calls the writer with path and parent")
    func folderMoveCallsWriter() async throws {
        let notes = MockNotesService()
        try await withNotes(notes) {
            let command = try FolderMoveCommand.parse(["Projects/Ideas", "--parent", "Archive", "--format", "json"])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.moveFolderCalled)
        #expect(notes.lastMovedFolderPath == "Projects/Ideas")
        #expect(notes.lastMovedFolderParent == "Archive")
    }

    @Test("folder delete calls the writer with path")
    func folderDeleteCallsWriter() async throws {
        let notes = MockNotesService()
        try await withNotes(notes) {
            let command = try FolderDeleteCommand.parse(["Projects/Ideas", "--format", "json"])
            try await discardStdout { try await command.run() }
        }
        #expect(notes.deleteFolderCalled)
        #expect(notes.lastDeletedFolderPath == "Projects/Ideas")
    }
}

@Suite("Command Read Tests", .serialized)
struct CommandReadTests {
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

    @Test("notes list matches unqualified folder filter against scoped paths")
    func notesListMatchesUnqualifiedFolderFilter() async throws {
        let notes = MockNotesService()
        notes.notes = [
            makeSampleAppleNote(id: "n1", name: "Scoped", bodyPlaintext: "One", folder: "iCloud/Projects/Ideas"),
            makeSampleAppleNote(id: "n2", name: "Other", bodyPlaintext: "Two", folder: "iCloud/Archive")
        ]

        let config = try InitCommandConfigService()
        config.loadedConfig = Config(notes: .init(selectedAccount: "iCloud"))

        try await withOverrides(notes: notes, config: config) {
            let command = try NotesListCommand.parse(["--folder", "Projects/Ideas", "--format", "json"])
            let output = try await captureStdout {
                try await command.run()
            }

            #expect(notes.fetchAllNotesCalled)
            #expect(output.contains("Scoped"))
            #expect(!output.contains("Other"))
        }
    }

    @Test("notes search matches unqualified folder filter against scoped paths")
    func notesSearchMatchesUnqualifiedFolderFilter() async throws {
        let notes = MockNotesService()
        notes.notes = [
            makeSampleAppleNote(id: "n1", name: "Scoped Search", bodyPlaintext: "Hello", folder: "iCloud/Projects/Ideas"),
            makeSampleAppleNote(id: "n2", name: "Wrong Folder", bodyPlaintext: "Hello", folder: "iCloud/Archive")
        ]

        let config = try InitCommandConfigService()
        config.loadedConfig = Config(notes: .init(selectedAccount: "iCloud"))

        try await withOverrides(notes: notes, config: config) {
            let command = try NotesSearchCommand.parse(["Hello", "--folder", "Projects/Ideas", "--format", "json"])
            let output = try await captureStdout {
                try await command.run()
            }

            #expect(notes.searchNotesCalled)
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
}

final class InitCommandConfigService: ConfigServiceProtocol, @unchecked Sendable {
    let rootDirectory: URL
    var loadedConfig: Config = .default
    var savedConfig: Config?

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

    func notesDirectory() throws -> URL {
        rootDirectory
    }
}
