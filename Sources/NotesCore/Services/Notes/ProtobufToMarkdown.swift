import Foundation
import SwiftProtobuf

// MARK: - Public Output Types (unchanged)

/// Result of converting a protobuf note body to Markdown.
public struct ProtobufConversionResult: Sendable {
    public let markdown: String
    public let plaintext: String
    public let attachments: [AttachmentReference]
}

/// Reference to an attachment found during protobuf decoding.
public struct AttachmentReference: Sendable {
    public let uuid: String
    public let typeUTI: String
}

// MARK: - Enums

/// Apple Notes paragraph style types. Ref: obsidian models.ts ANStyleType
private enum StyleType: Int32 {
    case title = 0
    case heading = 1
    case subheading = 2
    case monospaced = 4
    case dottedList = 100
    case dashedList = 101
    case numberedList = 102
    case checkbox = 103
}

/// Known attachment UTI types. Ref: obsidian models.ts ANAttachment
private enum AttachmentType: String {
    case drawing = "com.apple.paper"
    case drawingLegacy = "com.apple.drawing"
    case drawingLegacy2 = "com.apple.drawing.2"
    case hashtag = "com.apple.notes.inlinetextattachment.hashtag"
    case mention = "com.apple.notes.inlinetextattachment.mention"
    case internalLink = "com.apple.notes.inlinetextattachment.link"
    case modifiedScan = "com.apple.paper.doc.scan"
    case scan = "com.apple.notes.gallery"
    case table = "com.apple.notes.table"
    case urlCard = "public.url"
}

private let listStyles: Set<Int32> = [
    StyleType.dottedList.rawValue,
    StyleType.dashedList.rawValue,
    StyleType.numberedList.rawValue,
    StyleType.checkbox.rawValue,
]

/// Regex to match Apple Notes internal links.
/// Ref: obsidian convert-note.ts line 21 NOTE_URI
// swiftlint:disable:next force_try
private let noteURIPattern = try! NSRegularExpression( // safe: compile-time constant pattern
    pattern: #"applenotes:note/([-0-9a-f]+)(?:\?ownerIdentifier=.*)?"#
)

// MARK: - Converter

/// Converts Apple Notes protobuf data (gzipped) to Markdown.
public enum ProtobufToMarkdown {

    // MARK: - Public API

    /// Decode a gzipped protobuf note body and convert to Markdown + plaintext.
    ///
    /// - Parameters:
    ///   - data: Raw `ZDATA` blob from `ZICNOTEDATA` (gzip-compressed protobuf).
    ///   - resolver: Resolves inline attachments (hashtags, tables, links) during conversion.
    /// - Returns: Markdown, plaintext, and attachment references found in the note.
    /// - Throws: If decompression or protobuf decoding fails.
    public static func convert(data: Data, resolver: AttachmentResolver) throws -> ProtobufConversionResult {
        let decompressed = try Gzip.decompress(data)
        let proto = try Ciofecaforensics_NoteStoreProto(serializedBytes: decompressed)
        let note = proto.document.note
        let plaintext = note.noteText

        var mapper = MarkdownMapper(note: note, resolver: resolver)
        let markdown = mapper.map()

        return ProtobufConversionResult(
            markdown: markdown,
            plaintext: plaintext,
            attachments: mapper.attachments
        )
    }

    /// Lightweight plaintext extraction: gunzip + protobuf decode + read noteText.
    /// No markdown conversion and no attachment resolution.
    public static func plaintext(from data: Data) throws -> String {
        let decompressed = try Gzip.decompress(data)
        let proto = try Ciofecaforensics_NoteStoreProto(serializedBytes: decompressed)
        return proto.document.note.noteText
    }

    public static func extractPlaintext(from data: Data) -> String {
        (try? plaintext(from: data)) ?? ""
    }

}

// MARK: - Mapper

/// Simple linear mapper: walks attributeRun[], slices text, emits markdown.
private struct MarkdownMapper {
    let note: Ciofecaforensics_Note
    let resolver: AttachmentResolver

    var attachments: [AttachmentReference] = []

    // Minimal state
    private var inCodeBlock = false
    private var listNumber: Int = 0
    private var listIndent: Int = -1

    init(note: Ciofecaforensics_Note, resolver: AttachmentResolver) {
        self.note = note
        self.resolver = resolver
    }

    mutating func map() -> String {
        let runs = note.attributeRun
        let text = note.noteText
        guard !runs.isEmpty else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Pre-pass: merge adjacent runs with identical formatting
        let merged = mergeRuns(runs: runs, text: text)

        var output = ""
        var lineStart = true

        for (run, rawSlice) in merged {
            // Strip U+FFFC
            let slice = rawSlice.replacingOccurrences(of: "\u{FFFC}", with: "")

            // Code block state transitions
            let styleType = run.paragraphStyle.hasStyleType ? run.paragraphStyle.styleType : -1
            if styleType == StyleType.monospaced.rawValue && !inCodeBlock {
                if output.last != "\n" { output += "\n" }
                output += "```\n"
                inCodeBlock = true
            } else if styleType != StyleType.monospaced.rawValue && inCodeBlock {
                if output.last != "\n" { output += "\n" }
                output += "```\n"
                inCodeBlock = false
            }

            // Attachment dispatch
            if run.hasAttachmentInfo {
                output += formatAttachment(run)
                lineStart = output.last == "\n"
                continue
            }

            // Inside code block: raw text, no formatting
            if inCodeBlock {
                output += slice
                lineStart = slice.last == "\n"
                continue
            }

            // Split on newlines for paragraph handling
            let lines = slice.split(separator: "\n", omittingEmptySubsequences: false)
            for (lineIdx, line) in lines.enumerated() {
                let chunk = String(line)

                // Emit newline between sub-lines (not before first)
                if lineIdx > 0 {
                    output += "\n"
                    lineStart = true
                }

                if chunk.isEmpty { continue }

                // Apply inline formatting
                var formatted = applyInline(chunk, run: run)

                // Apply paragraph prefix at line start
                if lineStart {
                    formatted = applyParagraph(run, text: formatted)
                }

                output += formatted
                lineStart = false
            }
        }

        // Close open code block
        if inCodeBlock {
            if output.last != "\n" { output += "\n" }
            output += "```\n"
        }

        return MarkdownPostProcessor.run(output)
    }

    // MARK: - Run Merging

    /// Merge adjacent runs to eliminate word-splitting artifacts.
    ///
    /// Two merge strategies:
    /// 1. Identical formatting → always merge (Apple Notes splits arbitrarily)
    /// 2. Mid-word boundary → merge using the longer run's attrs
    ///    (Apple Notes often puts 1-2 chars in a different run than the rest of the word)
    private func mergeRuns(
        runs: [Ciofecaforensics_AttributeRun],
        text: String
    ) -> [(Ciofecaforensics_AttributeRun, String)] {
        var merged: [(Ciofecaforensics_AttributeRun, String)] = []
        var cursor = text.startIndex

        for run in runs {
            let length = Int(run.length)
            let end = text.index(cursor, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
            let slice = String(text[cursor..<end])
            cursor = end

            guard let lastIdx = merged.indices.last else {
                merged.append((run, slice))
                continue
            }

            // Same formatting → always merge
            if attrsMatch(merged[lastIdx].0, run) {
                merged[lastIdx].1 += slice
                continue
            }

            // Different formatting but mid-word → merge using longer run's attrs
            // (skip attachments — they need separate handling)
            if !merged[lastIdx].0.hasAttachmentInfo && !run.hasAttachmentInfo,
               let lastChar = merged[lastIdx].1.last,
               let firstChar = slice.first,
               isWordChar(lastChar), isWordChar(firstChar) {
                let lastText = merged[lastIdx].1
                let attrs = lastText.count >= slice.count ? merged[lastIdx].0 : run
                merged[lastIdx] = (attrs, lastText + slice)
                continue
            }

            merged.append((run, slice))
        }

        return merged
    }

    private func isWordChar(_ char: Character) -> Bool {
        char.isLetter || char.isNumber
            || char == "-" || char == "\u{2013}" || char == "\u{2014}"  // dashes
            || char == "." || char == ","                                // decimal/thousand separators
    }

    /// Compare two runs ignoring length — same formatting = mergeable.
    private func attrsMatch(
        _ lhs: Ciofecaforensics_AttributeRun,
        _ rhs: Ciofecaforensics_AttributeRun
    ) -> Bool {
        lhs.paragraphStyle == rhs.paragraphStyle
            && lhs.fontWeight == rhs.fontWeight
            && lhs.underlined == rhs.underlined
            && lhs.strikethrough == rhs.strikethrough
            && lhs.link == rhs.link
            && lhs.attachmentInfo == rhs.attachmentInfo
            && lhs.superscript == rhs.superscript
    }

    // MARK: - Inline Formatting

    private func applyInline(_ text: String, run: Ciofecaforensics_AttributeRun) -> String {
        let hasLink = run.hasLink && run.link != text
        let styleType = run.paragraphStyle.hasStyleType ? run.paragraphStyle.styleType : -1
        let isHeading = styleType == StyleType.title.rawValue
            || styleType == StyleType.heading.rawValue
            || styleType == StyleType.subheading.rawValue
        // Skip bold/underline on headings and links (link styling leaks as underline/bold)
        let suppressBold = isHeading || hasLink

        var result = text

        result = InlineMarkdownFormatter.apply(
            to: result,
            fontWeight: suppressBold ? nil : run.fontWeight,
            underlined: run.underlined != 0 && !suppressBold,
            strikethrough: run.strikethrough != 0
        )

        // Links
        if hasLink {
            if let uuid = extractNoteURI(run.link) {
                if let title = resolver.resolveInternalLink(uuid: uuid) {
                    let escaped = title
                        .replacingOccurrences(of: "|", with: "\\|")
                        .replacingOccurrences(of: "]", with: "\\]")
                    result = "[[\(escaped)]]"
                } else {
                    result = "[[unknown note]]"
                }
            } else {
                let url = run.link
                if url.contains(")") {
                    result = "[\(result)](<\(url)>)"
                } else {
                    result = "[\(result)](\(url))"
                }
            }
        }

        return result
    }

    // MARK: - Paragraph Formatting

    private mutating func applyParagraph(
        _ run: Ciofecaforensics_AttributeRun, text: String
    ) -> String {
        let styleType = run.paragraphStyle.hasStyleType ? run.paragraphStyle.styleType : -1
        let indentAmount = Int(run.paragraphStyle.indentAmount)
        let indent = String(repeating: "    ", count: indentAmount)
        let quoteDepth = Int(run.paragraphStyle.blockQuote)
        let quote = quoteDepth > 0 ? String(repeating: "> ", count: quoteDepth) : ""

        // Reset numbered list counter on style/indent change
        if listNumber != 0
            && (styleType != StyleType.numberedList.rawValue || listIndent != indentAmount) {
            listNumber = 0
        }
        listIndent = indentAmount

        switch StyleType(rawValue: styleType) {
        case .title: return "\(quote)# \(text)"
        case .heading: return "\(quote)## \(text)"
        case .subheading: return "\(quote)### \(text)"
        case .dottedList, .dashedList: return "\(quote)\(indent)- \(text)"
        case .numberedList:
            listNumber += 1
            return "\(quote)\(indent)\(listNumber). \(text)"
        case .checkbox:
            let checked = run.paragraphStyle.checklist.done != 0 ? "[x]" : "[ ]"
            return "\(quote)\(indent)- \(checked) \(text)"
        case .monospaced:
            return text  // raw inside code block
        default:
            return "\(quote)\(text)"
        }
    }

    // MARK: - Attachments

    private mutating func formatAttachment(_ run: Ciofecaforensics_AttributeRun) -> String {
        let uuid = run.attachmentInfo.attachmentIdentifier
        let typeUTI = run.attachmentInfo.typeUti
        guard !uuid.isEmpty else { return "" }

        switch AttachmentType(rawValue: typeUTI) {
        case .hashtag, .mention:
            return resolver.resolveInlineText(uuid: uuid) ?? ""

        case .internalLink:
            if let title = resolver.resolveInternalLink(uuid: uuid) {
                let escaped = title
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "]", with: "\\]")
                return "[[\(escaped)]]"
            }
            return "[[unknown note]]"

        case .table:
            if let data = resolver.resolveTableData(uuid: uuid) {
                do {
                    if let markdown = try TableConverter.convert(data: data) {
                        return "\n\(markdown)\n"
                    }
                } catch {
                    Log.debug(
                        "[protobuf] table conversion failed uuid=\(uuid) error=\(error)",
                        logger: Log.general
                    )
                }
            }
            return ""

        case .urlCard:
            if let card = resolver.resolveURLCard(uuid: uuid) {
                return "[\(card.title)](\(card.url))"
            }
            return ""

        case .scan, .modifiedScan, .drawing, .drawingLegacy, .drawingLegacy2:
            attachments.append(AttachmentReference(uuid: uuid, typeUTI: typeUTI))
            return "\n![[attachment:\(uuid):\(typeUTI)]]\n"

        case nil:
            attachments.append(AttachmentReference(uuid: uuid, typeUTI: typeUTI))
            return "\n![[attachment:\(uuid):\(typeUTI)]]\n"
        }
    }

    // MARK: - Helpers

    private func extractNoteURI(_ link: String) -> String? {
        let range = NSRange(link.startIndex..., in: link)
        guard let match = noteURIPattern.firstMatch(in: link, range: range),
              let uuidRange = Range(match.range(at: 1), in: link) else { return nil }
        return String(link[uuidRange])
    }
}

// MARK: - Markdown Post-Processing

private enum MarkdownPostProcessor {
    static func run(_ output: String) -> String {
        var result = normalizeUnicode(output)
        result = removeBoldArtifacts(result)
        result = addBlankLinesBeforeHeadings(result)
        result = stripCalculatorResults(result)
        result = processNonCodeLines(result)
        result = trimTrailingWhitespace(result)
        result = removeEmptyMarkers(result)
        result = normalizeDividers(result)
        result = collapseBlankLines(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeUnicode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    private static func removeBoldArtifacts(_ text: String) -> String {
        text
            .replacingOccurrences(of: "****", with: "")
            .replacingOccurrences(of: #"\*\*\s+\*\*"#, with: " ", options: .regularExpression)
    }

    private static func addBlankLinesBeforeHeadings(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?m)([^\n])\n(#{1,3} )"#, with: "$1\n\n$2", options: .regularExpression
        )
    }

    private static func stripCalculatorResults(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?m)^[0-9,.\s+\-*/]+\n!\[\[attachment:[^\]]*calculateresult[^\]]*\]\]\n?"#,
                with: "", options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?m)^!\[\[attachment:[^\]]*calculateresult[^\]]*\]\]\n?"#,
                with: "", options: .regularExpression
            )
    }

    private static func processNonCodeLines(_ text: String) -> String {
        var inCodeBlock = false
        var seenH1 = false

        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var str = String(line)
            if str.hasPrefix("```") {
                inCodeBlock.toggle()
                return str
            }
            guard !inCodeBlock else { return str }

            str = wrapBareURLs(str)
            if str.hasPrefix("# ") && !str.hasPrefix("## ") {
                if seenH1 { return "##" + str.dropFirst(1) }
                seenH1 = true
            }
            return str
        }.joined(separator: "\n")
    }

    private static func wrapBareURLs(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"(?<!\(|<|\[)https?://[^\s\)\]>]+"#,
            with: "[$0]($0)", options: .regularExpression
        )
    }

    private static func trimTrailingWhitespace(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    private static func removeEmptyMarkers(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?m)^-$\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^#{1,3}$\n?"#, with: "", options: .regularExpression)
    }

    private static func normalizeDividers(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2E3A}", with: "\n---\n")
            .replacingOccurrences(of: "\u{2E3B}", with: "\n---\n")
    }

    private static func collapseBlankLines(_ text: String) -> String {
        text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    }
}
