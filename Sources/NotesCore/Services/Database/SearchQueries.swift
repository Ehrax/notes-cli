import Foundation
import GRDB

extension DatabaseService {
    public func searchNotes(query: String) async throws -> [Note] {
        try await searchNotes(ftsColumn: "noteFts", query: query)
    }

    public func searchNotes(title query: String) async throws -> [Note] {
        try await searchNotes(ftsColumn: "noteFts.title", query: query)
    }

    public func searchNotes(body query: String) async throws -> [Note] {
        try await searchNotes(ftsColumn: "noteFts.bodyPlaintext", query: query)
    }

    private func searchNotes(ftsColumn: String, query: String) async throws -> [Note] {
        try await dbQueue.read { database in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else { return [] }

            let sql = """
                SELECT note.* FROM note
                JOIN noteFts ON noteFts.rowid = note.rowid
                WHERE \(ftsColumn) MATCH ?
                ORDER BY bm25(noteFts)
                """
            return try Note.fetchAll(database, sql: sql, arguments: [pattern])
        }
    }
}
