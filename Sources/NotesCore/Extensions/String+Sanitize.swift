import Foundation

extension String {
    /// Replaces only the first occurrence of a target string.
    public func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = self.range(of: target) else { return self }
        return self.replacingCharacters(in: range, with: replacement)
    }

    /// Strips HTML tags and trims whitespace.
    public var strippingHTML: String {
        self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    /// Escapes special characters for safe interpolation into AppleScript strings.
    ///
    /// AppleScript does NOT support C-style escape sequences like `\"` or `\\`.
    /// Instead, string concatenation with `quote` and `return` constants is used:
    /// - `"` → `" & quote & "` (breaks out of the string, concatenates the quote constant)
    /// - `\` → `" & "\\" & "` (backslash is literal in AppleScript, but we still protect it)
    /// - Newlines → `" & return & "` (AppleScript's return constant)
    /// - Control characters → stripped (replaced with space)
    public var sanitizedForAppleScript: String {
        var result = ""
        result.reserveCapacity(self.count + self.count / 4)
        for scalar in self.unicodeScalars {
            switch scalar {
            case "\"":
                // AppleScript: close string, concat `quote`, reopen string
                result.append("\" & quote & \"")
            case "\n", "\r":
                // AppleScript: close string, concat `return`, reopen string
                result.append("\" & return & \"")
            case "\t":
                // AppleScript: close string, concat `ASCII character 9`, reopen string
                result.append("\" & (ASCII character 9) & \"")
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    result.append(" ")
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
