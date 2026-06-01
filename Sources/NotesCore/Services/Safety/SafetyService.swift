import Foundation

/// Concrete implementation of SafetyServiceProtocol.
/// Depends on protocol-typed database and notes services.
public final class SafetyService: SafetyServiceProtocol, @unchecked Sendable {
    private let config: @Sendable () async throws -> Config
    private let db: DatabaseServiceProtocol
    private let notes: NotesServiceProtocol

    public init(
        configProvider: @escaping @Sendable () async throws -> Config,
        db: DatabaseServiceProtocol,
        notes: NotesServiceProtocol
    ) {
        self.config = configProvider
        self.db = db
        self.notes = notes
    }

    // MARK: - Guard operations

    public func guardWrite(toFolder folderPath: String) async throws {
        let cfg = try await config()
        let folderVariants = cfg.notes.folderPathVariants(for: folderPath)
        for protected in cfg.protectedFolders {
            let protectedVariants = cfg.notes.folderPathVariants(for: protected)
            if folderVariants.contains(where: { folderVariant in
                protectedVariants.contains(where: { protectedVariant in
                    folderVariant == protectedVariant || folderVariant.hasPrefix(protectedVariant + "/")
                })
            }) {
                Log.notice("[safety.guard] write_blocked folder=\"\(folderPath)\" matched_rule=\"\(protected)\"", logger: Log.safety)
                throw NotesError.protectedFolder(path: folderPath)
            }
        }
        Log.debug("[safety.guard] write_allowed folder=\"\(folderPath)\"", logger: Log.safety)
    }

    public func guardLocked(noteID: String, isLocked: Bool) async throws {
        let cfg = try await config()
        if isLocked && cfg.lockedNotes {
            throw NotesError.noteLocked(id: noteID)
        }
    }

    // MARK: - Soft delete

    public func softDelete(noteID: String) async throws {
        let raw = try await notes.fetchNote(id: noteID)
        guard let raw else {
            throw NotesError.noteNotFound(id: noteID)
        }

        try await guardWrite(toFolder: raw.folderPath)

        let beforeCheckpoint = Checkpoint(
            noteID: raw.id,
            title: raw.name,
            bodyProtobuf: raw.bodyProtobuf,
            bodyPlaintext: raw.bodyPlaintext,
            folderPath: raw.folderPath
        )

        let cfg = try await config()

        if cfg.softDelete {
            let archiveFolderPath = notes.scopedFolderPath("Archive")
            // Perform mutation first, then record on success
            Log.info("[safety.delete] soft_delete note_id=\(noteID) destination=\"Archive\"", logger: Log.safety)
            try await notes.moveNote(id: noteID, toFolder: archiveFolderPath)
            var archivedFallback = Note(from: raw, syncedAt: Date())
            archivedFallback.folderPath = archiveFolderPath
            try await refreshNoteInDatabase(noteID: noteID, fallback: archivedFallback)
            try await recordAction(
                type: .softDelete,
                noteID: noteID,
                before: beforeCheckpoint,
                after: nil,
                metadata: ["destination": archiveFolderPath]
            )
        } else {
            Log.info("[safety.delete] hard_delete note_id=\(noteID)", logger: Log.safety)
            try await notes.deleteNote(id: noteID)
            try await recordAction(
                type: .delete,
                noteID: noteID,
                before: beforeCheckpoint,
                after: nil,
                metadata: nil
            )
            try await db.deleteNote(id: noteID)
        }
    }

    // MARK: - Action recording

    public func recordAction(
        type: ActionType,
        noteID: String,
        before: Checkpoint?,
        after: Checkpoint?,
        metadata: [String: String]?
    ) async throws {
        let record = try ActionLogger.makeRecord(
            type: type,
            noteID: noteID,
            before: before,
            after: after,
            metadata: metadata
        )
        _ = try await db.insertActionRecord(record)
    }

    // MARK: - Undo

    public func undoLast() async throws -> UndoResult? {
        guard let lastAction = try await db.fetchLatestUndoableAction() else {
            return nil
        }

        let reverseOp = try UndoService.reverseOperation(for: lastAction)
        Log.info("[safety.undo] reversing action_type=\(lastAction.actionType.rawValue) note_id=\(lastAction.noteID)", logger: Log.safety)
        let cfg = try await config()

        // Execute the reverse operation with safety guards
        switch reverseOp {
        case .deleteNote(let noteID):
            // Undo of create: respect softDelete config
            if let raw = try await notes.fetchNote(id: noteID) {
                try await guardWrite(toFolder: raw.folderPath)
            }
            if cfg.softDelete {
                let archiveFolderPath = notes.scopedFolderPath("Archive")
                try await notes.moveNote(id: noteID, toFolder: archiveFolderPath)
                if let raw = try await notes.fetchNote(id: noteID) {
                    try await refreshNoteInDatabase(noteID: noteID, fallback: Note(from: raw, syncedAt: Date()))
                } else if let existingNote = try await db.fetchNote(id: noteID) {
                    var archivedFallback = existingNote
                    archivedFallback.folderPath = archiveFolderPath
                    archivedFallback.syncedAt = Date()
                    try await refreshNoteInDatabase(noteID: noteID, fallback: archivedFallback)
                }
            } else {
                try await notes.deleteNote(id: noteID)
                try await db.deleteNote(id: noteID)
            }

        case .restoreNote(let checkpoint):
            try await guardWrite(toFolder: checkpoint.folderPath)
            // Temporary: use plaintext for restore until protobuf→markdown conversion is wired
            let restoreHTML = checkpoint.bodyPlaintext
            try await notes.updateNote(
                id: checkpoint.noteID,
                title: checkpoint.title,
                bodyHTML: restoreHTML
            )
            try await refreshNoteInDatabase(noteID: checkpoint.noteID, fallback: note(from: checkpoint))

        case .recreateNote(let checkpoint):
            try await guardWrite(toFolder: checkpoint.folderPath)
            // Temporary: use plaintext for recreate until protobuf→markdown conversion is wired
            let recreateHTML = checkpoint.bodyPlaintext
            let recreatedID = try await notes.createNote(
                title: checkpoint.title,
                bodyHTML: recreateHTML,
                folderName: checkpoint.folderPath
            )
            if let raw = try await notes.fetchNote(id: recreatedID) {
                try await db.insertNote(Note(from: raw, syncedAt: Date()))
            } else {
                try await db.insertNote(note(from: checkpoint, id: recreatedID))
            }

        case .moveNote(let noteID, let toFolder):
            try await guardWrite(toFolder: toFolder)
            try await notes.moveNote(id: noteID, toFolder: toFolder)
            let fallback = try await db.fetchNote(id: noteID).map { note in
                var updatedNote = note
                updatedNote.folderPath = toFolder
                updatedNote.syncedAt = Date()
                return updatedNote
            }
            try await refreshNoteInDatabase(noteID: noteID, fallback: fallback)
        }

        // Mark the action as undone
        var updated = lastAction
        updated.undone = true
        try await db.updateActionRecord(updated)

        guard let actionID = lastAction.id else {
            return nil
        }

        return UndoResult(
            actionID: actionID,
            originalType: lastAction.actionType,
            description: UndoService.description(for: lastAction.actionType, noteID: lastAction.noteID)
        )
    }

    // MARK: - History

    public func history(noteID: String?, limit: Int) async throws -> [ActionSummary] {
        let records: [ActionRecord]
        if let noteID {
            records = try await db.fetchActionRecords(forNoteID: noteID)
        } else {
            records = try await db.fetchAllActionRecords(limit: limit)
        }

        return records.prefix(limit).map { ActionSummary(from: $0) }
    }

    private func refreshNoteInDatabase(noteID: String, fallback: Note?) async throws {
        if let raw = try await notes.fetchNote(id: noteID) {
            try await saveNoteInDatabase(Note(from: raw, syncedAt: Date()))
        } else if let fallback {
            try await saveNoteInDatabase(fallback)
        }
    }

    private func saveNoteInDatabase(_ note: Note) async throws {
        if try await db.fetchNote(id: note.id) != nil {
            try await db.updateNote(note)
        } else {
            try await db.insertNote(note)
        }
    }

    private func note(from checkpoint: Checkpoint, id: String? = nil) -> Note {
        Note(
            id: id ?? checkpoint.noteID,
            title: checkpoint.title,
            bodyProtobuf: checkpoint.bodyProtobuf,
            bodyPlaintext: checkpoint.bodyPlaintext,
            folderPath: notes.resolvedFolderPath(checkpoint.folderPath),
            syncedAt: Date()
        )
    }

}
