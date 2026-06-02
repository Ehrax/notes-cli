import Testing
@testable import NotesCore

@Suite("NoteHTML body composer")
struct NoteHTMLTests {
    @Test("bakes the title in as <h1> and adds a blank line before the body")
    func prependsTitleAndSpacesBody() {
        let body = NoteHTML.composeBody(title: "Peniche", contentHTML: "<div>Prose.</div>")
        #expect(body == "<h1>Peniche</h1><div><br></div><div>Prose.</div>")
    }

    @Test("blanks surround each <h2> section heading (before and after)")
    func spacesAroundH2() {
        let body = NoteHTML.composeBody(title: "T", contentHTML: "<div>a</div><h2>Sec</h2><div>b</div>")
        #expect(body == "<h1>T</h1><div><br></div><div>a</div><div><br></div><h2>Sec</h2><div><br></div><div>b</div>")
    }

    @Test("leaves <h3> subheadings tight against their content")
    func keepsH3Tight() {
        let body = NoteHTML.composeBody(title: "T", contentHTML: "<div>a</div><h3>Sub</h3><div>b</div>")
        #expect(body == "<h1>T</h1><div><br></div><div>a</div><h3>Sub</h3><div>b</div>")
    }

    @Test("adds a blank line after a list, but lets it cling to its intro line")
    func spacesAfterLists() {
        let body = NoteHTML.composeBody(title: "T", contentHTML: "<div>intro:</div><ul><li>x</li></ul><div>after</div>")
        #expect(body == "<h1>T</h1><div><br></div><div>intro:</div><ul><li>x</li></ul><div><br></div><div>after</div>")
    }

    @Test("is idempotent — does not double-space already-spaced HTML")
    func collapsesExistingBlanks() {
        let body = NoteHTML.composeBody(title: "T", contentHTML: "<div>a</div><div><br></div><h2>Sec</h2><div>b</div>")
        #expect(body == "<h1>T</h1><div><br></div><div>a</div><div><br></div><h2>Sec</h2><div><br></div><div>b</div>")
    }

    @Test("with no title, spaces the content and trims leading/trailing blanks")
    func noTitleSpacesAndTrims() {
        #expect(NoteHTML.composeBody(title: nil, contentHTML: "<h2>Sec</h2><div>b</div>")
            == "<h2>Sec</h2><div><br></div><div>b</div>")
        #expect(NoteHTML.composeBody(title: "   ", contentHTML: "<div>x</div>") == "<div>x</div>")
    }

    @Test("empty content yields just the title, no trailing blank")
    func emptyContentIsTitleOnly() {
        #expect(NoteHTML.composeBody(title: "T", contentHTML: "") == "<h1>T</h1>")
    }

    @Test("escapes HTML-significant characters in the title")
    func escapesTitle() {
        #expect(NoteHTML.composeBody(title: "Tom & <Jerry>", contentHTML: "") == "<h1>Tom &amp; &lt;Jerry&gt;</h1>")
    }

    @Test("footer credits the model in italic with a robot icon, separated by a blank line")
    func footerWithModel() {
        #expect(NoteHTML.footer(model: "Claude Opus 4.8")
            == "<div><br></div><div><i>🤖 Created by Claude Opus 4.8 via notes-cli</i></div>")
    }

    @Test("footer falls back to a generic credit when the model is unknown")
    func footerWithoutModel() {
        let expected = "<div><br></div><div><i>🤖 Created by an AI assistant via notes-cli</i></div>"
        #expect(NoteHTML.footer(model: nil) == expected)
        #expect(NoteHTML.footer(model: "  ") == expected)
    }

    @Test("footer escapes HTML-significant characters in the model name")
    func footerEscapesModel() {
        #expect(NoteHTML.footer(model: "Ada & <Lovelace>")
            == "<div><br></div><div><i>🤖 Created by Ada &amp; &lt;Lovelace&gt; via notes-cli</i></div>")
    }
}
