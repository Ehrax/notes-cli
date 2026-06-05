import Foundation

enum MarkdownPostProcessor {
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
