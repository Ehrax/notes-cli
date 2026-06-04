import Foundation

/// Builds the HTML body sent to Apple Notes' ScriptingBridge `body` property.
///
/// Apple Notes derives a note's title from the first line of its body, so the title must
/// live *inside* the body — never as a separate `name` set alongside it (that renders twice).
/// `composeBody` bakes the title in as a leading `<h1>` so callers pass the title once and
/// get a single, styled title line.
public enum NoteHTML {
    /// An empty paragraph — the only way to get vertical space between blocks in Apple Notes.
    private static let blank = "<div><br></div>"

    /// Returns `contentHTML` with `title` baked in as an `<h1>` first line and section spacing
    /// applied. An empty/whitespace/`nil` title leaves only the spaced content.
    static func composeBody(title: String?, contentHTML: String) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw: String
        if let trimmed, !trimmed.isEmpty {
            raw = "<h1>\(escape(trimmed))</h1>\(contentHTML)"
        } else {
            raw = contentHTML
        }
        return spaceSections(raw)
    }

    /// Converts editor/plaintext content into simple HTML before it reaches the ScriptingBridge writer.
    public static func plainTextHTML(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { "<div>\(escape($0))</div>" }
            .joined()
    }

    /// Give sections room to breathe: a blank paragraph before *and* after each top-level heading
    /// (`<h1>`/`<h2>`) and after each list, so headings don't hug their text. `<h3>` subheadings
    /// stay tight against their content. Idempotent: runs of blanks collapse and edge blanks are
    /// trimmed, so already-spaced HTML passes through unchanged.
    static func spaceSections(_ html: String) -> String {
        var result = html
        // Blank before each top-level heading.
        result = result.replacingOccurrences(
            of: #"(<h[12](?:[ >]))"#, with: "\(blank)$1", options: .regularExpression
        )
        // Blank after each top-level heading and after each list.
        result = result.replacingOccurrences(
            of: #"(</h[12]>|</(?:ul|ol)>)"#, with: "$1\(blank)", options: .regularExpression
        )
        // Collapse runs of blanks, then trim leading/trailing ones.
        result = result.replacingOccurrences(
            of: #"(?:<div><br></div>){2,}"#, with: blank, options: .regularExpression
        )
        if result.hasPrefix(blank) { result = String(result.dropFirst(blank.count)) }
        if result.hasSuffix(blank) { result = String(result.dropLast(blank.count)) }
        return result
    }

    /// The AI-provenance footer appended to created notes: an italic, robot-prefixed credit on
    /// its own line, separated from the body by a blank paragraph. `model` names the LLM when
    /// known; otherwise it falls back to a generic credit.
    static func footer(model: String?) -> String {
        let who: String
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            who = escape(model)
        } else {
            who = "an AI assistant"
        }
        return "\(blank)<div><i>🤖 Created by \(who) via notes-cli</i></div>"
    }

    /// Escape the characters that would otherwise break out of the `<h1>` text node.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
