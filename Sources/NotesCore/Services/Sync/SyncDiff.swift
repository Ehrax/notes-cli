import Foundation

/// The result of a sync operation.
public struct SyncResult: Codable, Sendable, Equatable {
    public var added: Int
    public var updated: Int
    public var deleted: Int
    public var unchanged: Int
    public var errors: [SyncError]

    public init(
        added: Int = 0,
        updated: Int = 0,
        deleted: Int = 0,
        unchanged: Int = 0,
        errors: [SyncError] = []
    ) {
        self.added = added
        self.updated = updated
        self.deleted = deleted
        self.unchanged = unchanged
        self.errors = errors
    }

    public static func == (lhs: SyncResult, rhs: SyncResult) -> Bool {
        lhs.added == rhs.added
            && lhs.updated == rhs.updated
            && lhs.deleted == rhs.deleted
            && lhs.unchanged == rhs.unchanged
            && lhs.errors.count == rhs.errors.count
    }
}

/// An error that occurred for a specific note during sync.
public struct SyncError: Codable, Sendable {
    public var noteID: String?
    public var message: String

    public init(noteID: String? = nil, message: String) {
        self.noteID = noteID
        self.message = message
    }
}

/// The diff between Apple Notes and the local database.
public struct SyncDiff: Sendable {
    public var newNotes: [AppleNoteRaw]
    public var modifiedNotes: [AppleNoteRaw]
    public var deletedNoteIDs: [String]
    public var unchangedCount: Int

    public init(
        newNotes: [AppleNoteRaw] = [],
        modifiedNotes: [AppleNoteRaw] = [],
        deletedNoteIDs: [String] = [],
        unchangedCount: Int = 0
    ) {
        self.newNotes = newNotes
        self.modifiedNotes = modifiedNotes
        self.deletedNoteIDs = deletedNoteIDs
        self.unchangedCount = unchangedCount
    }
}
