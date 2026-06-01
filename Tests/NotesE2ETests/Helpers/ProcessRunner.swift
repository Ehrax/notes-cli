import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

/// Runs the `notes-cli` binary as a subprocess with the given arguments.
func runNotesCLI(
    _ arguments: [String],
    environment: [String: String]? = nil,
    timeout: TimeInterval = 10
) throws -> ProcessResult {
    let binaryPath = try findNotesCLIBinary()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = arguments

    if let environment {
        // Merge with current environment so PATH etc. are preserved
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    // Read pipes on background threads to avoid deadlock when the subprocess
    // fills the pipe buffer (~64KB). Reads MUST happen concurrently with the wait.
    var stdoutData = Data()
    var stderrData = Data()
    let group = DispatchGroup()

    group.enter()
    DispatchQueue.global().async {
        stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    group.enter()
    DispatchQueue.global().async {
        stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }

    // Wait for process exit with timeout
    let deadline = DispatchTime.now() + timeout
    let processGroup = DispatchGroup()
    processGroup.enter()
    DispatchQueue.global().async {
        process.waitUntilExit()
        processGroup.leave()
    }

    let waitResult = processGroup.wait(timeout: deadline)
    if waitResult == .timedOut {
        process.terminate()
        process.waitUntilExit()
        // Drain remaining pipe data after termination
        _ = group.wait(timeout: .now() + 2)
        return ProcessResult(
            exitCode: -1,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: "Process timed out after \(timeout)s"
        )
    }

    // Wait for pipe reads to complete
    _ = group.wait(timeout: .now() + 5)

    return ProcessResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}

/// Locates the notes-cli binary, checking NOTES_CLI_BINARY_PATH env var first, then build directory.
private func findNotesCLIBinary() throws -> String {
    // Check env var override first
    if let envPath = ProcessInfo.processInfo.environment["NOTES_CLI_BINARY_PATH"] {
        guard FileManager.default.fileExists(atPath: envPath) else {
            throw E2EError.binaryNotFound("NOTES_CLI_BINARY_PATH set to \(envPath) but file does not exist")
        }
        return envPath
    }

    // Derive from #filePath: Tests/NotesE2ETests/Helpers/ProcessRunner.swift
    // Project root is 4 levels up
    let thisFile = URL(fileURLWithPath: #filePath)
    let projectRoot = thisFile
        .deletingLastPathComponent() // Helpers/
        .deletingLastPathComponent() // NotesE2ETests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // project root

    let debugBinary = projectRoot
        .appendingPathComponent(".build")
        .appendingPathComponent("debug")
        .appendingPathComponent("notes-cli")

    guard FileManager.default.fileExists(atPath: debugBinary.path) else {
        throw E2EError.binaryNotFound(
            "Binary not found at \(debugBinary.path). Run `swift build` first, or set NOTES_CLI_BINARY_PATH."
        )
    }

    return debugBinary.path
}

enum E2EError: Error, CustomStringConvertible {
    case binaryNotFound(String)

    var description: String {
        switch self {
        case .binaryNotFound(let msg): return msg
        }
    }
}
