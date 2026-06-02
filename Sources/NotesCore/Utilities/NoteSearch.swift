import Foundation

/// Pure, stateless search ranking over already-decoded notes.
/// Case-insensitive substring match against title or plaintext body,
/// kept matches sorted by modification date (most recent first), capped at `limit`.
public enum NoteSearch {
    public static func rank(notes: [AppleNoteRaw], query: String, limit: Int) -> [AppleNoteRaw] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        return notes
            .filter { note in
                note.name.lowercased().contains(needle)
                    || note.bodyPlaintext.lowercased().contains(needle)
            }
            .sorted { $0.modificationDate > $1.modificationDate }
            .prefix(max(0, limit))
            .map { $0 }
    }
}
