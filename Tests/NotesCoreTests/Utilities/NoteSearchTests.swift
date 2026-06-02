import Foundation
import Testing

@testable import NotesCore
import NotesTestSupport

@Suite("NoteSearch Tests")
struct NoteSearchTests {
    private func note(
        id: String,
        title: String = "Untitled",
        body: String = "",
        modified: Date
    ) -> AppleNoteRaw {
        makeSampleAppleNote(
            id: id,
            name: title,
            bodyPlaintext: body,
            modificationDate: modified
        )
    }

    @Test("matches against the title only")
    func matchesTitleOnly() {
        let notes = [note(id: "n1", title: "Grocery list", body: "milk", modified: Date())]
        let results = NoteSearch.rank(notes: notes, query: "grocery", limit: 10)
        #expect(results.map(\.id) == ["n1"])
    }

    @Test("matches against the body only")
    func matchesBodyOnly() {
        let notes = [note(id: "n1", title: "Untitled", body: "remember the milk", modified: Date())]
        let results = NoteSearch.rank(notes: notes, query: "milk", limit: 10)
        #expect(results.map(\.id) == ["n1"])
    }

    @Test("matching is case-insensitive")
    func matchesCaseInsensitive() {
        let notes = [note(id: "n1", title: "PROJECT Alpha", body: "Details", modified: Date())]
        let results = NoteSearch.rank(notes: notes, query: "project", limit: 10)
        #expect(results.map(\.id) == ["n1"])
    }

    @Test("orders matches by modification date descending")
    func ordersByRecency() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let notes = [
            note(id: "old", title: "meeting", modified: base),
            note(id: "new", title: "meeting", modified: base.addingTimeInterval(100)),
            note(id: "mid", title: "meeting", modified: base.addingTimeInterval(50))
        ]
        let results = NoteSearch.rank(notes: notes, query: "meeting", limit: 10)
        #expect(results.map(\.id) == ["new", "mid", "old"])
    }

    @Test("caps results at the limit")
    func capsAtLimit() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let notes = (0..<5).map { idx in
            note(id: "n\(idx)", title: "match", modified: base.addingTimeInterval(Double(idx)))
        }
        let results = NoteSearch.rank(notes: notes, query: "match", limit: 2)
        #expect(results.count == 2)
        #expect(results.map(\.id) == ["n4", "n3"])
    }

    @Test("returns empty when nothing matches")
    func returnsEmptyOnNoMatch() {
        let notes = [note(id: "n1", title: "alpha", body: "beta", modified: Date())]
        let results = NoteSearch.rank(notes: notes, query: "zzz", limit: 10)
        #expect(results.isEmpty)
    }

    @Test("returns empty for an empty query")
    func returnsEmptyForEmptyQuery() {
        let notes = [note(id: "n1", title: "alpha", body: "beta", modified: Date())]
        let results = NoteSearch.rank(notes: notes, query: "", limit: 10)
        #expect(results.isEmpty)
    }
}
