import Foundation
import Testing
import SwiftProtobuf
import NotesTestSupport
@testable import NotesCore

// MARK: - Gzip Helper

/// Wraps a raw deflate payload in a minimal gzip envelope (RFC 1952).
/// Used to create test fixtures for ProtobufToMarkdown.convert(data:resolver:).
private func gzipWrap(_ deflatePayload: Data) -> Data {
    // CRC32 computation (simple rolling implementation)
    func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        let table: [UInt32] = (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            return value
        }
        for byte in data {
            let tableIndex = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[tableIndex]
        }
        return crc ^ 0xFFFF_FFFF
    }

    var result = Data()

    // Gzip header: ID1, ID2, CM, FLG, MTIME(4), XFL, OS
    result.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00])  // magic + deflate + no flags
    result.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // modification time = 0
    result.append(contentsOf: [0x00, 0xFF])               // XFL=0, OS=unknown

    // The deflate payload (raw compressed stream)
    result.append(deflatePayload)

    // Gzip trailer: CRC32 and ISIZE (must be original data size, but here we don't track it)
    // For our tests we pass 0 for both since gunzip only needs the deflate payload
    let crc = crc32(deflatePayload)  // placeholder CRC
    result.append(UInt8((crc >> 0) & 0xFF))
    result.append(UInt8((crc >> 8) & 0xFF))
    result.append(UInt8((crc >> 16) & 0xFF))
    result.append(UInt8((crc >> 24) & 0xFF))
    result.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // ISIZE = 0 (only used for verification)

    return result
}

/// Creates gzip-compressed protobuf data suitable for ProtobufToMarkdown.convert(data:resolver:).
private func makeNoteData(noteText: String, runs: [Ciofecaforensics_AttributeRun]) throws -> Data {
    var note = Ciofecaforensics_Note()
    note.noteText = noteText
    note.attributeRun = runs

    var document = Ciofecaforensics_Document()
    document.version = 1
    document.note = note

    var proto = Ciofecaforensics_NoteStoreProto()
    proto.document = document

    let serialized = try proto.serializedData()

    // Compress using raw deflate via NSData
    guard let compressed = try? (serialized as NSData).compressed(using: .zlib) as Data else {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Compression failed"])
    }

    return gzipWrap(compressed)
}

/// Builds a simple AttributeRun covering `text.count` characters.
private func makeRun(
    text: String,
    styleType: Int32? = nil,
    fontWeight: Int32? = nil,
    underlined: Int32? = nil,
    strikethrough: Int32? = nil,
    link: String? = nil,
    indentAmount: Int32? = nil,
    blockQuote: Int32? = nil,
    alignment: Int32? = nil,
    checklist: Ciofecaforensics_Checklist? = nil,
    attachmentUUID: String? = nil,
    attachmentUTI: String? = nil
) -> Ciofecaforensics_AttributeRun {
    var run = Ciofecaforensics_AttributeRun()
    run.length = Int32(text.unicodeScalars.count)

    var para = Ciofecaforensics_ParagraphStyle()
    if let st = styleType { para.styleType = st }
    if let ia = indentAmount { para.indentAmount = ia }
    if let bq = blockQuote { para.blockQuote = bq }
    if let al = alignment { para.alignment = al }
    if let cl = checklist { para.checklist = cl }
    run.paragraphStyle = para

    if let fw = fontWeight { run.fontWeight = fw }
    if let ul = underlined { run.underlined = ul }
    if let st = strikethrough { run.strikethrough = st }
    if let lk = link { run.link = lk }

    if let uuid = attachmentUUID {
        var info = Ciofecaforensics_AttachmentInfo()
        info.attachmentIdentifier = uuid
        if let uti = attachmentUTI { info.typeUti = uti }
        run.attachmentInfo = info
    }

    return run
}

// MARK: - Tests

@Suite("ProtobufToMarkdown")
struct ProtobufToMarkdownTests {

    // MARK: - No runs

    @Test("Plain text with no runs returns text as-is")
    func plainTextNoRuns() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(noteText: "Hello, world!", runs: [])
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "Hello, world!")
        #expect(result.plaintext == "Hello, world!")
        #expect(result.attachments.isEmpty)
    }

    // MARK: - Headings

    @Test("Title renders as H1")
    func title() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "My Title\n",
            runs: [makeRun(text: "My Title\n", styleType: 0)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "# My Title")
    }

    @Test("Heading renders as H2")
    func heading() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Section\n",
            runs: [makeRun(text: "Section\n", styleType: 1)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "## Section")
    }

    @Test("Subheading renders as H3")
    func subheading() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Sub\n",
            runs: [makeRun(text: "Sub\n", styleType: 2)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "### Sub")
    }

    // MARK: - Bold heading suppression

    @Test("Bold on heading is suppressed — heading implies emphasis")
    func boldOnHeadingSuppressed() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Title\n",
            runs: [makeRun(text: "Title\n", styleType: 0, fontWeight: 1)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "# Title")
        #expect(!result.markdown.contains("**"))
    }

    // MARK: - Inline formatting

    @Test("Bold text")
    func bold() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Bold text\n",
            runs: [makeRun(text: "Bold text\n", fontWeight: 1)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "**Bold text**")
    }

    @Test("Italic renders as plain text")
    func italic() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Italic text\n",
            runs: [makeRun(text: "Italic text\n", fontWeight: 2)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "Italic text")
    }

    @Test("BoldItalic renders as bold only")
    func boldItalic() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Mixed\n",
            runs: [makeRun(text: "Mixed\n", fontWeight: 3)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "**Mixed**")
    }

    @Test("Underline renders as bold")
    func underline() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Underlined\n",
            runs: [makeRun(text: "Underlined\n", underlined: 1)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "**Underlined**")
    }

    @Test("Strikethrough renders with tildes")
    func strikethrough() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Struck\n",
            runs: [makeRun(text: "Struck\n", strikethrough: 1)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "~~Struck~~")
    }

    // MARK: - Mixed inline within a line

    @Test("Bold then plain on same line")
    func boldThenPlain() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Hello World\n",
            runs: [
                makeRun(text: "Hello ", fontWeight: 1),
                makeRun(text: "World\n"),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "**Hello** World")
    }

    @Test("Adjacent bold runs merge into single span")
    func adjacentBoldRunsMerge() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Focus:\n",
            runs: [
                makeRun(text: "F", fontWeight: 1),
                makeRun(text: "ocus:\n", fontWeight: 1),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "**Focus:**")
    }

    @Test("Mid-word split with different formatting merges using longer run's attrs")
    func midWordMerge() throws {
        let resolver = MockAttachmentResolver()
        // "H" is plain, "allo," is bold → mid-word → merge → bold wins (longer)
        let data = try makeNoteData(
            noteText: "Hallo,\n",
            runs: [
                makeRun(text: "H"),
                makeRun(text: "allo,\n", fontWeight: 1),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "**Hallo,**")
    }

    @Test("Split link text merges at word boundary — bare URL wrapped as link")
    func splitLinkMerge() throws {
        let resolver = MockAttachmentResolver()
        // "h" plain + "ttps://example.com" with link → merge → bare URL → wrapped
        let data = try makeNoteData(
            noteText: "https://example.com\n",
            runs: [
                makeRun(text: "h"),
                makeRun(text: "ttps://example.com\n", link: "https://example.com"),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "[https://example.com](https://example.com)")
        #expect(!result.markdown.contains("h[ttps"))  // no split
    }

    @Test("Bold link text has no bold markers — link styling suppressed")
    func boldLinkSuppressed() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Click here\n",
            runs: [makeRun(text: "Click here\n", fontWeight: 1, link: "https://example.com")]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "[Click here](https://example.com)")
        #expect(!result.markdown.contains("**"))
    }

    @Test("Underlined link text has no bold markers")
    func underlinedLinkSuppressed() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Click here\n",
            runs: [makeRun(text: "Click here\n", underlined: 1, link: "https://example.com")]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "[Click here](https://example.com)")
        #expect(!result.markdown.contains("**"))
    }

    // MARK: - Links

    @Test("External link")
    func externalLink() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Click here\n",
            runs: [makeRun(text: "Click here\n", link: "https://example.com")]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "[Click here](https://example.com)")
    }

    @Test("URL with parentheses uses angle brackets")
    func urlWithParens() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Link\n",
            runs: [makeRun(text: "Link\n", link: "https://example.com/page_(1)")]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "[Link](<https://example.com/page_(1)>)")
    }

    @Test("Internal link resolves to wiki-link")
    func internalLink() throws {
        let resolver = MockAttachmentResolver()
        resolver.internalLinks["link-uuid"] = "My Note"
        let data = try makeNoteData(
            noteText: "\u{FFFC}\n",
            runs: [makeRun(
                text: "\u{FFFC}\n",
                attachmentUUID: "link-uuid",
                attachmentUTI: "com.apple.notes.inlinetextattachment.link"
            )]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("[[My Note]]"))
    }

    // MARK: - Lists

    @Test("Unordered list")
    func unorderedList() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Item One\nItem Two\n",
            runs: [
                makeRun(text: "Item One\n", styleType: 100),
                makeRun(text: "Item Two\n", styleType: 100),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("- Item One"))
        #expect(result.markdown.contains("- Item Two"))
    }

    @Test("Numbered list")
    func numberedList() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "First\nSecond\n",
            runs: [
                makeRun(text: "First\n", styleType: 102),
                makeRun(text: "Second\n", styleType: 102),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("1. First"))
        #expect(result.markdown.contains("2. Second"))
    }

    @Test("Indented list items use 4 spaces")
    func indentedList() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Parent\nChild\n",
            runs: [
                makeRun(text: "Parent\n", styleType: 100),
                makeRun(text: "Child\n", styleType: 100, indentAmount: 1),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("- Parent"))
        #expect(result.markdown.contains("    - Child"))
    }

    @Test("Checkbox unchecked")
    func checkboxUnchecked() throws {
        let resolver = MockAttachmentResolver()
        var checklist = Ciofecaforensics_Checklist()
        checklist.done = 0
        checklist.uuid = Data("u1".utf8)
        let data = try makeNoteData(
            noteText: "Todo\n",
            runs: [makeRun(text: "Todo\n", styleType: 103, checklist: checklist)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "- [ ] Todo")
    }

    @Test("Checkbox checked")
    func checkboxChecked() throws {
        let resolver = MockAttachmentResolver()
        var checklist = Ciofecaforensics_Checklist()
        checklist.done = 1
        checklist.uuid = Data("u2".utf8)
        let data = try makeNoteData(
            noteText: "Done\n",
            runs: [makeRun(text: "Done\n", styleType: 103, checklist: checklist)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "- [x] Done")
    }

    // MARK: - Code block

    @Test("Code block fenced")
    func codeBlock() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "let x = 1\n",
            runs: [makeRun(text: "let x = 1\n", styleType: 4)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("```"))
        #expect(result.markdown.contains("let x = 1"))
    }

    // MARK: - Blockquote

    @Test("Blockquote with depth")
    func blockquote() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Quoted\n",
            runs: [makeRun(text: "Quoted\n", blockQuote: 1)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "> Quoted")
    }

    @Test("Nested blockquote")
    func nestedBlockquote() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Deep\n",
            runs: [makeRun(text: "Deep\n", blockQuote: 2)]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown == "> > Deep")
    }

    // MARK: - Attachments

    @Test("Hashtag resolves inline")
    func hashtag() throws {
        let resolver = MockAttachmentResolver()
        resolver.inlineTexts["tag-1"] = "#travel"
        let data = try makeNoteData(
            noteText: "Going on a trip \u{FFFC}\n",
            runs: [
                makeRun(text: "Going on a trip "),
                makeRun(
                    text: "\u{FFFC}\n",
                    attachmentUUID: "tag-1",
                    attachmentUTI: "com.apple.notes.inlinetextattachment.hashtag"
                ),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("#travel"))
    }

    @Test("Hashtag-only line and trailing #Capitalized survive as text")
    func hashtagsSurvive() throws {
        let resolver = MockAttachmentResolver()
        resolver.inlineTexts["tag-travel"] = "#travel"
        resolver.inlineTexts["tag-cap"] = "#Capitalized"
        let data = try makeNoteData(
            noteText: "Body line\n\u{FFFC}\nMore body \u{FFFC}\n",
            runs: [
                makeRun(text: "Body line\n"),
                makeRun(
                    text: "\u{FFFC}\n",
                    attachmentUUID: "tag-travel",
                    attachmentUTI: "com.apple.notes.inlinetextattachment.hashtag"
                ),
                makeRun(text: "More body "),
                makeRun(
                    text: "\u{FFFC}\n",
                    attachmentUUID: "tag-cap",
                    attachmentUTI: "com.apple.notes.inlinetextattachment.hashtag"
                ),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("#travel"))
        #expect(result.markdown.contains("#Capitalized"))
    }

    @Test("URL card renders as plain link — no bold on link text")
    func urlCard() throws {
        let resolver = MockAttachmentResolver()
        resolver.urlCards["card-1"] = (title: "Example", url: "https://example.com")
        let data = try makeNoteData(
            noteText: "\u{FFFC}\n",
            runs: [makeRun(
                text: "\u{FFFC}\n",
                attachmentUUID: "card-1",
                attachmentUTI: "public.url"
            )]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("[Example](https://example.com)"))
        #expect(!result.markdown.contains("**"))
    }

    @Test("File attachment produces wikilink placeholder")
    func fileAttachment() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "\u{FFFC}\n",
            runs: [makeRun(
                text: "\u{FFFC}\n",
                attachmentUUID: "img-1",
                attachmentUTI: "public.jpeg"
            )]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("![[attachment:img-1:public.jpeg]]"))
        #expect(result.attachments.count == 1)
    }

    // MARK: - U+FFFC cleanup

    @Test("No U+FFFC leaks in output")
    func noFFFC() throws {
        let resolver = MockAttachmentResolver()
        resolver.inlineTexts["h-1"] = "#tag"
        let data = try makeNoteData(
            noteText: "Before \u{FFFC} after\n",
            runs: [
                makeRun(text: "Before "),
                makeRun(text: "\u{FFFC}", attachmentUUID: "h-1",
                         attachmentUTI: "com.apple.notes.inlinetextattachment.hashtag"),
                makeRun(text: " after\n"),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(!result.markdown.contains("\u{FFFC}"))
    }

    // MARK: - Error handling

    @Test("Corrupt data throws")
    func corruptData() {
        let resolver = MockAttachmentResolver()
        #expect(throws: (any Error).self) {
            try ProtobufToMarkdown.convert(data: Data([0xFF, 0xFE]), resolver: resolver)
        }
    }

    @Test("Empty data throws")
    func emptyData() {
        let resolver = MockAttachmentResolver()
        #expect(throws: (any Error).self) {
            try ProtobufToMarkdown.convert(data: Data(), resolver: resolver)
        }
    }

    // MARK: - Plaintext extraction

    @Test("extractPlaintext returns raw noteText")
    func extractPlaintext() throws {
        let data = try makeNoteData(
            noteText: "Hello World",
            runs: [makeRun(text: "Hello World", fontWeight: 1)]
        )
        let result = ProtobufToMarkdown.extractPlaintext(from: data)
        #expect(result == "Hello World")
    }

    // MARK: - Multi-paragraph

    @Test("Title + body + list renders correctly")
    func multiParagraph() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Title\nSome body text\nItem one\nItem two\n",
            runs: [
                makeRun(text: "Title\n", styleType: 0),
                makeRun(text: "Some body text\n"),
                makeRun(text: "Item one\n", styleType: 100),
                makeRun(text: "Item two\n", styleType: 100),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(result.markdown.contains("# Title"))
        #expect(result.markdown.contains("Some body text"))
        #expect(result.markdown.contains("- Item one"))
        #expect(result.markdown.contains("- Item two"))
    }

    // MARK: - No HTML in output

    @Test("Output contains no HTML tags")
    func noHTML() throws {
        let resolver = MockAttachmentResolver()
        let data = try makeNoteData(
            noteText: "Under\nBold\nStruck\n",
            runs: [
                makeRun(text: "Under\n", underlined: 1),
                makeRun(text: "Bold\n", fontWeight: 1),
                makeRun(text: "Struck\n", strikethrough: 1),
            ]
        )
        let result = try ProtobufToMarkdown.convert(data: data, resolver: resolver)
        #expect(!result.markdown.contains("<"))
        #expect(!result.markdown.contains(">"))
    }
}
