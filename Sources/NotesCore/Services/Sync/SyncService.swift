import Foundation

/// Keeps the local SQLite database in sync with Apple Notes.
public final class SyncService: SyncServiceProtocol, Sendable {
    private let db: DatabaseServiceProtocol
    private let notes: NotesServiceProtocol

    private enum SyncMode {
        case full
        case incremental(lastSync: Date?)
    }

    private struct HydrationCandidate {
        let metadata: AppleNoteMetadata
        let existingNote: Note?
    }

    public static let lastSyncKey = "lastSyncTimestamp"

    public init(db: DatabaseServiceProtocol, notes: NotesServiceProtocol) {
        self.db = db
        self.notes = notes
    }

    // MARK: - Full Sync

    public func fullSync() async throws -> SyncResult {
        Log.info("[sync.full] started", logger: Log.sync)
        let start = CFAbsoluteTimeGetCurrent()

        let appleNotes = try await notes.fetchAllNotes()
        let dbNotes = try await db.fetchAllNotes()
        Log.debug("[sync.full] fetched notes apple_count=\(appleNotes.count) db_count=\(dbNotes.count)", logger: Log.sync)

        let diff = computeFullDiff(appleNotes: appleNotes, dbNotes: dbNotes)
        Log.debug("[sync.full] diff computed new=\(diff.newNotes.count) modified=\(diff.modifiedNotes.count) deleted=\(diff.deletedNoteIDs.count)", logger: Log.sync)

        let result = try await applyDiff(diff)

        try await syncFolders()
        if result.errors.isEmpty {
            try await updateSyncTimestamp()
        } else {
            Log.notice("[sync.full] skipped_timestamp_update error_count=\(result.errors.count)", logger: Log.sync)
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.info("[sync.full] completed added=\(result.added) updated=\(result.updated) deleted=\(result.deleted) duration_ms=\(durationMs)", logger: Log.sync)

        return result
    }

    // MARK: - Incremental Sync

    public func incrementalSync() async throws -> SyncResult {
        let lastSync = try await lastSyncDate()
        return try await performSync(mode: .incremental(lastSync: lastSync))
    }

    // MARK: - Internal

    private func computeFullDiff(appleNotes: [AppleNoteRaw], dbNotes: [Note]) -> SyncDiff {
        let dbMap = Dictionary(dbNotes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let appleIDs = Set(appleNotes.map(\.id))
        let dbIDs = Set(dbNotes.map(\.id))

        var newNotes: [AppleNoteRaw] = []
        var modifiedNotes: [AppleNoteRaw] = []
        var unchangedCount = 0

        for raw in appleNotes {
            if let existing = dbMap[raw.id] {
                if hasChanged(raw: raw, comparedTo: existing) {
                    modifiedNotes.append(raw)
                } else {
                    unchangedCount += 1
                }
            } else {
                newNotes.append(raw)
            }
        }

        return SyncDiff(
            newNotes: newNotes,
            modifiedNotes: modifiedNotes,
            deletedNoteIDs: Array(dbIDs.subtracting(appleIDs)),
            unchangedCount: unchangedCount
        )
    }

    private func performSync(mode: SyncMode) async throws -> SyncResult {
        let logPrefix: String
        switch mode {
        case .full:
            logPrefix = "sync.full"
        case .incremental:
            logPrefix = "sync.incremental"
        }
        Log.info("[\(logPrefix)] started", logger: Log.sync)
        let start = CFAbsoluteTimeGetCurrent()

        let appleMetadata = try await notes.fetchAllNoteMetadata()
        let dbNotes = try await db.fetchAllNotes()
        Log.debug(
            "[\(logPrefix)] fetched metadata apple_count=\(appleMetadata.count) db_count=\(dbNotes.count)",
            logger: Log.sync
        )

        let plan = makeHydrationPlan(appleMetadata: appleMetadata, dbNotes: dbNotes, mode: mode)
        let diff = try await hydrateDiff(from: plan)
        Log.debug(
            "[\(logPrefix)] diff computed new=\(diff.diff.newNotes.count) modified=\(diff.diff.modifiedNotes.count) deleted=\(diff.diff.deletedNoteIDs.count) hydrated=\(plan.candidates.count)",
            logger: Log.sync
        )

        let applied = try await applyDiff(diff.diff)
        let result = SyncResult(
            added: applied.added,
            updated: applied.updated,
            deleted: applied.deleted,
            unchanged: applied.unchanged,
            errors: applied.errors + diff.errors
        )

        try await syncFolders()
        if result.errors.isEmpty {
            try await updateSyncTimestamp()
        } else {
            Log.notice("[\(logPrefix)] skipped_timestamp_update error_count=\(result.errors.count)", logger: Log.sync)
        }

        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.info(
            "[\(logPrefix)] completed added=\(result.added) updated=\(result.updated) deleted=\(result.deleted) duration_ms=\(durationMs)",
            logger: Log.sync
        )

        return result
    }

    private func makeHydrationPlan(appleMetadata: [AppleNoteMetadata], dbNotes: [Note], mode: SyncMode) -> (candidates: [HydrationCandidate], deletedNoteIDs: [String], unchangedCount: Int) {
        let dbMap = Dictionary(dbNotes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let appleIDs = Set(appleMetadata.map(\.id))
        let dbIDs = Set(dbNotes.map(\.id))

        var candidates: [HydrationCandidate] = []
        var unchangedCount = 0

        for metadata in appleMetadata {
            let existingNote = dbMap[metadata.id]

            if existingNote == nil {
                candidates.append(HydrationCandidate(metadata: metadata, existingNote: nil))
                continue
            }

            if shouldHydrate(metadata: metadata, existingNote: existingNote, mode: mode) {
                candidates.append(HydrationCandidate(metadata: metadata, existingNote: existingNote))
            } else {
                unchangedCount += 1
            }
        }

        return (candidates, Array(dbIDs.subtracting(appleIDs)), unchangedCount)
    }

    private func hydrateDiff(from plan: (candidates: [HydrationCandidate], deletedNoteIDs: [String], unchangedCount: Int)) async throws
        -> (diff: SyncDiff, errors: [SyncError])
    {
        var newNotes: [AppleNoteRaw] = []
        var modifiedNotes: [AppleNoteRaw] = []
        var unchangedCount = plan.unchangedCount
        var errors: [SyncError] = []

        for candidate in plan.candidates {
            do {
                guard let raw = try await notes.fetchNote(id: candidate.metadata.id) else {
                    errors.append(SyncError(noteID: candidate.metadata.id, message: "Note metadata was present but full note fetch returned no result"))
                    continue
                }

                if let existingNote = candidate.existingNote {
                    if hasChanged(raw: raw, comparedTo: existingNote) {
                        modifiedNotes.append(raw)
                    } else {
                        unchangedCount += 1
                    }
                } else {
                    newNotes.append(raw)
                }
            } catch {
                Log.error("[sync] hydrate_failed note_id=\(candidate.metadata.id) error=\"\(error.localizedDescription)\"", logger: Log.sync)
                errors.append(SyncError(noteID: candidate.metadata.id, message: error.localizedDescription))
            }
        }

        return (
            SyncDiff(
                newNotes: newNotes,
                modifiedNotes: modifiedNotes,
                deletedNoteIDs: plan.deletedNoteIDs,
                unchangedCount: unchangedCount
            ),
            errors
        )
    }

    private func shouldHydrate(metadata: AppleNoteMetadata, existingNote: Note?, mode: SyncMode) -> Bool {
        guard let existingNote else { return true }

        switch mode {
        case .full:
            return true
        case .incremental(let lastSync):
            guard let lastSync else { return true }
            return metadata.modificationDate > lastSync || metadataHasChanged(metadata, comparedTo: existingNote)
        }
    }

    func applyDiff(_ diff: SyncDiff) async throws -> SyncResult {
        var added = 0
        var updated = 0
        var deleted = 0
        var errors: [SyncError] = []

        // Insert new notes
        for raw in diff.newNotes {
            do {
                let note = convertToNote(raw)
                try await db.insertNote(note)
                try await syncAttachments(noteID: raw.id)
                added += 1
            } catch {
                Log.error("[sync] insert_failed note_id=\(raw.id) error=\"\(error.localizedDescription)\"", logger: Log.sync)
                errors.append(SyncError(noteID: raw.id, message: error.localizedDescription))
            }
        }

        // Update modified notes
        for raw in diff.modifiedNotes {
            do {
                let note = convertToNote(raw)
                try await db.updateNote(note)
                try await syncAttachments(noteID: raw.id)
                updated += 1
            } catch {
                Log.error("[sync] update_failed note_id=\(raw.id) error=\"\(error.localizedDescription)\"", logger: Log.sync)
                errors.append(SyncError(noteID: raw.id, message: error.localizedDescription))
            }
        }

        // Delete removed notes (cascades to noteAttachment via FK)
        for noteID in diff.deletedNoteIDs {
            do {
                try await db.deleteNote(id: noteID)
                deleted += 1
            } catch {
                Log.error("[sync] delete_failed note_id=\(noteID) error=\"\(error.localizedDescription)\"", logger: Log.sync)
                errors.append(SyncError(noteID: noteID, message: error.localizedDescription))
            }
        }

        return SyncResult(
            added: added,
            updated: updated,
            deleted: deleted,
            unchanged: diff.unchangedCount,
            errors: errors
        )
    }

    private func syncAttachments(noteID: String) async throws {
        let attachments = try await notes.fetchAttachments(noteID: noteID)
        try await db.deleteAttachments(forNoteID: noteID)
        for attachment in attachments {
            try await db.insertAttachment(attachment)
        }
    }

    func convertToNote(_ raw: AppleNoteRaw) -> Note {
        Note(from: raw, syncedAt: Date())
    }

    private func syncFolders() async throws {
        let appleFolders = try await notes.fetchFolders()
        let dbFolders = try await db.fetchAllFolders()
        let dbFoldersByID = Dictionary(uniqueKeysWithValues: dbFolders.map { ($0.id, $0) })
        let dbFoldersByPath = Dictionary(uniqueKeysWithValues: dbFolders.map { ($0.path, $0) })
        var appleFolderIDs = Set<String>()
        var seenPaths = Set<String>()

        for raw in appleFolders {
            // Skip duplicate paths (safety net for cross-account collisions)
            guard seenPaths.insert(raw.path).inserted else { continue }
            appleFolderIDs.insert(raw.id)
            let folder = Folder(
                id: raw.id,
                name: raw.name,
                path: raw.path,
                parentPath: raw.parentPath
            )

            if dbFoldersByID[raw.id] != nil {
                try await db.updateFolder(folder)
            } else if let existing = dbFoldersByPath[raw.path] {
                // Path exists with a different ID — update the existing record
                var updated = folder
                updated.id = existing.id
                try await db.updateFolder(updated)
            } else {
                try await db.insertFolder(folder)
            }
        }

        // Delete folders no longer in Apple Notes by stable folder identity.
        for dbFolder in dbFolders {
            if !appleFolderIDs.contains(dbFolder.id) {
                try await db.deleteFolder(path: dbFolder.path)
            }
        }
    }

    private func updateSyncTimestamp() async throws {
        try await db.setSyncState(key: Self.lastSyncKey, value: Date().iso8601String)
    }

    private func lastSyncDate() async throws -> Date? {
        guard let value = try await db.getSyncState(key: Self.lastSyncKey) else {
            return nil
        }
        return Date.fromISO8601(value)
    }

    private func metadataHasChanged(_ metadata: AppleNoteMetadata, comparedTo note: Note) -> Bool {
        note.title != metadata.name
            || note.folderPath != metadata.folderPath
            || !timestampsMatch(note.creationDate, metadata.creationDate)
            || !timestampsMatch(note.modificationDate, metadata.modificationDate)
            || note.isLocked != metadata.isLocked
    }

    private func hasChanged(raw: AppleNoteRaw, comparedTo note: Note) -> Bool {
        note.title != raw.name
            || note.folderPath != raw.folderPath
            || !timestampsMatch(note.creationDate, raw.creationDate)
            || !timestampsMatch(note.modificationDate, raw.modificationDate)
            || note.isLocked != raw.isLocked
            || note.checksum != Note.computeChecksum(raw.bodyProtobuf)
    }

    private func timestampsMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        Int(lhs.timeIntervalSince1970) == Int(rhs.timeIntervalSince1970)
    }
}
