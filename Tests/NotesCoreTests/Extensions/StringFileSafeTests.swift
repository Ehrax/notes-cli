import Testing
@testable import NotesCore

@Suite("String+FileSafe")
struct StringFileSafeTests {
    @Test func sanitizesSlashes() {
        #expect("foo/bar".fileSafe == "foo-bar")
    }

    @Test func sanitizesColons() {
        #expect("foo:bar".fileSafe == "foo-bar")
    }

    @Test func sanitizesNullBytes() {
        #expect("foo\0bar".fileSafe == "foo-bar")
    }

    @Test func sanitizesNewlines() {
        #expect("foo\nbar".fileSafe == "foo-bar")
        #expect("foo\rbar".fileSafe == "foo-bar")
    }

    @Test func trimsWhitespaceAndDots() {
        #expect("  .hello. ".fileSafe == "hello")
    }

    @Test func truncatesLongNames() {
        let long = String(repeating: "a", count: 250)
        #expect(long.fileSafe.count == 200)
    }

    @Test func handlesEmptyString() {
        #expect("".fileSafe == "Untitled")
    }

    @Test func handlesOnlySpecialChars() {
        #expect("///".fileSafe == "Untitled")
    }
}
