import Foundation
import os

/// Centralized logging for notes-cli CLI using Apple's unified logging system.
/// Uses `os.Logger` for Console.app integration and mirrors to stderr when verbose.
public enum Log {
    private static let subsystem = "dev.ehrax.notes-cli"

    // MARK: - Per-service loggers

    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let database = Logger(subsystem: subsystem, category: "database")
    public static let applescript = Logger(subsystem: subsystem, category: "applescript")
    public static let safety = Logger(subsystem: subsystem, category: "safety")
    public static let config = Logger(subsystem: subsystem, category: "config")
    public static let reminders = Logger(subsystem: subsystem, category: "reminders")
    public static let general = Logger(subsystem: subsystem, category: "general")

    // MARK: - Verbose flag

    /// Set once at startup from `--verbose` flag. Controls stderr mirroring.
    nonisolated(unsafe) public static var isVerbose: Bool = false

    // MARK: - Convenience methods

    public static func debug(_ message: String, logger: Logger) {
        logger.debug("\(message, privacy: .private)")
        if isVerbose {
            printStderr("[debug] \(message)")
        }
    }

    public static func info(_ message: String, logger: Logger) {
        logger.info("\(message, privacy: .private)")
        if isVerbose {
            printStderr("[info]  \(message)")
        }
    }

    public static func notice(_ message: String, logger: Logger) {
        logger.notice("\(message, privacy: .private)")
        if isVerbose {
            printStderr("[notice] \(message)")
        }
    }

    public static func error(_ message: String, logger: Logger) {
        logger.error("\(message, privacy: .private)")
        if isVerbose {
            printStderr("[error] \(message)")
        }
    }

    public static func fault(_ message: String, logger: Logger) {
        logger.fault("\(message, privacy: .private)")
        if isVerbose {
            printStderr("[fault] \(message)")
        }
    }

    // MARK: - Private

    private static let stderr = FileHandle.standardError
    private static let newline = Data([0x0A])

    private static func printStderr(_ message: String) {
        stderr.write(Data(message.utf8))
        stderr.write(newline)
    }
}
