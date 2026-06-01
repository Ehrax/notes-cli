import Foundation

/// Extracts checkboxes from note content (plain text or HTML).
public enum CheckboxParser {

    // MARK: - Public

    /// Parse checkboxes from note plain text or HTML content.
    ///
    /// Recognized patterns:
    /// - `- [ ] Task text` / `- [x] Completed task` (markdown)
    /// - `<li>` elements with checkbox markers from Apple Notes HTML
    /// - Optional `due:YYYY-MM-DD` at the end of a line
    public static func parse(_ text: String) -> [Checkbox] {
        guard !text.isEmpty else { return [] }

        if text.contains("<li") {
            let htmlCheckboxes = parseHTML(text)
            if !htmlCheckboxes.isEmpty {
                return htmlCheckboxes
            }
        }

        return parseMarkdown(text)
    }

    // MARK: - Private

    private static let dueDatePattern = #"\s+due:(\d{4}-\d{2}-\d{2})\s*$"#

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    // Cached regex instances
    private static let markdownRegex = try? NSRegularExpression(
        pattern: #"^[\t ]*-\s+\[([ xX])\]\s+(.+)$"#,
        options: .anchorsMatchLines
    )

    private static let htmlRegex = try? NSRegularExpression(
        // swiftlint:disable:next line_length
        pattern: #"<li[^>]*?\bclass\s*=\s*"([^"]*)"[^>]*>(.*?)</li>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let dueDateRegex = try? NSRegularExpression(
        pattern: dueDatePattern,
        options: []
    )

    /// Parse markdown-style checkboxes: `- [ ] text` and `- [x] text`.
    private static func parseMarkdown(_ text: String) -> [Checkbox] {
        guard let regex = markdownRegex else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match -> Checkbox? in
            guard match.numberOfRanges >= 3 else { return nil }
            let checkMark = nsText.substring(with: match.range(at: 1))
            let rawText = nsText.substring(with: match.range(at: 2))
            let isChecked = checkMark.lowercased() == "x"
            let (cleanText, dueDate) = extractDueDate(from: rawText)
            guard !cleanText.isEmpty else { return nil }
            return Checkbox(text: cleanText, isChecked: isChecked, dueDate: dueDate)
        }
    }

    /// Parse HTML checkbox patterns from Apple Notes.
    ///
    /// Apple Notes uses `<ul>` with `<li>` elements. Checked items typically include
    /// a marker attribute or class. We look for common patterns:
    /// - `<li class="checked">` or `<li class="done">`
    /// - `type="checkbox"` with `checked` attribute
    private static func parseHTML(_ text: String) -> [Checkbox] {
        // Only attempt HTML parsing if content looks like HTML
        guard text.contains("<li") else { return [] }
        guard let regex = htmlRegex else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match -> Checkbox? in
            guard match.numberOfRanges >= 3 else { return nil }
            let classValue = nsText.substring(with: match.range(at: 1))

            // Only process items that look like checkboxes
            let checkboxClasses = ["checked", "done", "unchecked", "todo", "checkbox"]
            let isCheckboxItem = checkboxClasses.contains { classValue.lowercased().contains($0) }
            guard isCheckboxItem else { return nil }

            let lowerClass = classValue.lowercased()
            let uncheckedClasses = ["unchecked", "todo"]
            let isUnchecked = uncheckedClasses.contains { lowerClass.contains($0) }
            let isChecked = !isUnchecked && ["checked", "done"].contains { lowerClass.contains($0) }

            let rawHTML = nsText.substring(with: match.range(at: 2))
            let plainText = rawHTML.strippingHTML
            guard !plainText.isEmpty else { return nil }

            let (cleanText, dueDate) = extractDueDate(from: plainText)
            guard !cleanText.isEmpty else { return nil }
            return Checkbox(text: cleanText, isChecked: isChecked, dueDate: dueDate)
        }
    }

    /// Extract an optional `due:YYYY-MM-DD` suffix from text.
    /// Returns the cleaned text and optional date.
    private static func extractDueDate(from text: String) -> (String, Date?) {
        guard let regex = dueDateRegex else { return (text, nil) }

        let nsText = text as NSString
        let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length))

        guard let match, match.numberOfRanges >= 2 else {
            return (text, nil)
        }

        let dateString = nsText.substring(with: match.range(at: 1))
        let cleanText = nsText.replacingCharacters(in: match.range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let date = dateFormatter.date(from: dateString)

        return (cleanText, date)
    }
}
