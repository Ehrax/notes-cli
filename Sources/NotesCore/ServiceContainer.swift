import Foundation

/// Central dependency container that lazily creates and wires all services.
public actor ServiceContainer {
    public static let shared = ServiceContainer()

    // MARK: - Overrides (for testing)

    private var _databaseOverride: (any DatabaseServiceProtocol)?
    private var _notesOverride: (any NotesServiceProtocol)?
    private var _syncOverride: (any SyncServiceProtocol)?
    private var _reminderOverride: (any ReminderServiceProtocol)?
    private var _safetyOverride: (any SafetyServiceProtocol)?
    private var _configOverride: (any ConfigServiceProtocol)?

    // MARK: - Cached instances

    private var _config: (any ConfigServiceProtocol)?
    private var _database: (any DatabaseServiceProtocol)?
    private var _notes: (any NotesServiceProtocol)?
    private var _sync: (any SyncServiceProtocol)?
    private var _reminder: (any ReminderServiceProtocol)?
    private var _safety: (any SafetyServiceProtocol)?

    // MARK: - Runtime overrides (non-test)

    private var _accountOverride: String?

    /// Override the account scope for this process run (does not persist to config).
    public func setAccountOverride(_ account: String) {
        _accountOverride = account
        // Reset notes/sync so they pick up the new scope
        _notes = nil
        _sync = nil
        _safety = nil
    }

    public init() {}

    // MARK: - Service accessors

    public var config: any ConfigServiceProtocol {
        get throws {
            if let override = _configOverride { return override }
            if let cached = _config { return cached }
            let service = ConfigService()
            _config = service
            return service
        }
    }

    public var database: any DatabaseServiceProtocol {
        get throws {
            if let override = _databaseOverride { return override }
            if let cached = _database { return cached }
            let configSvc = try config
            let dbPath = try configSvc.databasePath()
            let service = try DatabaseService(path: dbPath.path)
            _database = service
            return service
        }
    }

    public var notes: any NotesServiceProtocol {
        get async throws {
            if let override = _notesOverride { return override }
            if let cached = _notes { return cached }
            let configSvc = try config
            let notesDir = try configSvc.notesDirectory()
            let cacheDir = notesDir.appendingPathComponent("cache", isDirectory: true).path
            var cfg = try await configSvc.loadConfig()
            if let accountOverride = _accountOverride {
                cfg.notes.selectedAccount = accountOverride
            }
            let reader = NoteStoreReader(cacheDir: cacheDir)
            let writer = await AppleScriptWriter(runner: AppleScriptRunner(), scope: cfg.notes)
            let service = DirectNotesService(reader: reader, writer: writer, scope: cfg.notes)
            _notes = service
            return service
        }
    }

    public var sync: any SyncServiceProtocol {
        get async throws {
            if let override = _syncOverride { return override }
            if let cached = _sync { return cached }
            let db = try database
            let notesSvc = try await notes
            let service = SyncService(db: db, notes: notesSvc)
            _sync = service
            return service
        }
    }

    public var reminders: any ReminderServiceProtocol {
        get async throws {
            if let override = _reminderOverride { return override }
            if let cached = _reminder { return cached }
            let service = await ReminderService()
            _reminder = service
            return service
        }
    }

    public var attachmentResolver: any AttachmentResolver {
        get async throws {
            let configSvc = try config
            let notesDir = try configSvc.notesDirectory()
            let cacheDir = notesDir.appendingPathComponent("cache", isDirectory: true).path
            return NoteStoreReader(cacheDir: cacheDir)
        }
    }

    public var safety: any SafetyServiceProtocol {
        get async throws {
            if let override = _safetyOverride { return override }
            if let cached = _safety { return cached }
            let configSvc = try config
            let db = try database
            let notesSvc = try await notes
            let service = SafetyService(
                configProvider: { try await configSvc.loadConfig() },
                db: db,
                notes: notesSvc
            )
            _safety = service
            return service
        }
    }

    // MARK: - Override methods for testing

    public func override(database: (any DatabaseServiceProtocol)?) {
        _databaseOverride = database
        // Reset dependents
        _sync = nil
        _safety = nil
    }

    public func override(notes: (any NotesServiceProtocol)?) {
        _notesOverride = notes
        // Reset dependents
        _sync = nil
        _safety = nil
    }

    public func override(sync: (any SyncServiceProtocol)?) {
        _syncOverride = sync
    }

    public func override(reminders: (any ReminderServiceProtocol)?) {
        _reminderOverride = reminders
    }

    public func override(safety: (any SafetyServiceProtocol)?) {
        _safetyOverride = safety
    }

    public func override(config: (any ConfigServiceProtocol)?) {
        _configOverride = config
        // Reset dependents
        _database = nil
        _notes = nil
        _sync = nil
        _safety = nil
    }

    /// Resets all cached instances and overrides.
    public func reset() {
        _databaseOverride = nil
        _notesOverride = nil
        _syncOverride = nil
        _reminderOverride = nil
        _safetyOverride = nil
        _configOverride = nil
        _config = nil
        _database = nil
        _notes = nil
        _sync = nil
        _reminder = nil
        _safety = nil
    }
}
