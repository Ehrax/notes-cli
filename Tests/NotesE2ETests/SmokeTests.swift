import Foundation
import Testing

@Suite("E2E Smoke Tests")
struct SmokeTests {
    private func withIsolatedNotesCLIHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-cli-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }

    private func isolatedEnvironment(home: URL) -> [String: String] {
        ["NOTES_CLI_HOME": home.path]
    }

    // MARK: - notes-cli --help

    @Test("notes-cli --help exits 0 and contains abstract")
    func helpExitsZero() throws {
        let result = try runNotesCLI(["--help"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("AI-native Apple Notes CLI"))
    }

    // MARK: - notes-cli --version

    @Test("notes-cli --version exits 0 and contains version string")
    func versionExitsZero() throws {
        let result = try runNotesCLI(["--version"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("0.1.0"))
    }

    // MARK: - notes-cli init --yes

    @Test("notes-cli init --yes exits 0")
    func initYesExitsZero() throws {
        try withIsolatedNotesCLIHome { home in
            let result = try runNotesCLI(["init", "--yes", "--format", "json"], environment: isolatedEnvironment(home: home))
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.contains("initialized"))
        }
    }

    // MARK: - notes-cli notes list --format json

    @Test("notes-cli notes list --format json exits 0 or 2")
    func notesListJsonExits() throws {
        try withIsolatedNotesCLIHome { home in
            let environment = isolatedEnvironment(home: home)
            _ = try runNotesCLI(["init", "--yes", "--format", "json"], environment: environment)

            let result = try runNotesCLI(["notes", "list", "--format", "json"], environment: environment)
            #expect(result.exitCode == 0 || result.exitCode == 2)
        }
    }

    // MARK: - notes-cli nonexistent

    @Test("notes-cli nonexistent exits non-zero")
    func nonexistentCommandExitsNonZero() throws {
        let result = try runNotesCLI(["nonexistent"])
        #expect(result.exitCode != 0)
    }
}
