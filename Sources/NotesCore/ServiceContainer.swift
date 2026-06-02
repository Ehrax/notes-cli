import Foundation

/// Central dependency container that lazily creates and wires all services.
public actor ServiceContainer {
    public static let shared = ServiceContainer()

    // MARK: - Overrides (for testing)

    private var _notesOverride: (any NotesServiceProtocol)?
    private var _configOverride: (any ConfigServiceProtocol)?

    // MARK: - Cached instances

    private var _config: (any ConfigServiceProtocol)?
    private var _notes: (any NotesServiceProtocol)?

    // MARK: - Runtime overrides (non-test)

    private var _accountOverride: String?

    /// Override the account scope for this process run (does not persist to config).
    public func setAccountOverride(_ account: String) {
        _accountOverride = account
        // Reset notes so they pick up the new scope
        _notes = nil
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

    public var notes: any NotesServiceProtocol {
        get async throws {
            if let override = _notesOverride { return override }
            if let cached = _notes { return cached }
            let configSvc = try config
            var cfg = try await configSvc.loadConfig()
            if let accountOverride = _accountOverride {
                cfg.notes.selectedAccount = accountOverride
            }
            let reader = NoteStoreReader()
            let writer = await ScriptingBridgeWriter(scope: cfg.notes)
            let service = DirectNotesService(
                reader: reader, writer: writer, scope: cfg.notes, aiFooterEnabled: cfg.aiFooterEnabled
            )
            _notes = service
            return service
        }
    }

    public var attachmentResolver: any AttachmentResolver {
        get async throws {
            NoteStoreReader()
        }
    }

    // MARK: - Override methods for testing

    public func override(notes: (any NotesServiceProtocol)?) {
        _notesOverride = notes
    }

    public func override(config: (any ConfigServiceProtocol)?) {
        _configOverride = config
        // Reset dependents
        _notes = nil
    }

    /// Resets all cached instances and overrides.
    public func reset() {
        _notesOverride = nil
        _configOverride = nil
        _config = nil
        _notes = nil
    }
}
