import Foundation

extension Character {
    /// True if this character is an emoji (symbol presentation or emoji modifier sequence).
    var isEmoji: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmoji && scalar.value > 0x238C
        }
    }
}

extension String {
    /// Returns a filesystem-safe version of this string for use as a filename.
    public var fileSafe: String {
        let forbidden = CharacterSet(charactersIn: "/:\0\n\r")
        var result = unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? "-" : String(scalar)
        }.joined()
        // Trim whitespace, dots, and leading/trailing dashes
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        // Truncate
        if result.count > 200 {
            result = String(result.prefix(200))
        }
        // Fallback
        if result.isEmpty {
            result = "Untitled"
        }
        return result
    }

    /// Returns a clean export filename: lowercase, no emoji, spaces→dashes, filesystem-safe.
    public var exportFilename: String {
        // Strip date patterns from title (DD.MM.YY, DD.MM.YYYY, DD/MM/YY, etc.)
        // These mangle into digit sequences like 170920 when dots are stripped
        var result = self.replacingOccurrences(
            of: #"\d{1,2}[./]\d{1,2}[./]\d{2,4}"#, with: "", options: .regularExpression
        )
        // Keep only letters (including unicode like ä,ö,ü), numbers, spaces, dashes
        result = String(result.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" })
        result = result.lowercased()
        // Spaces → dashes, collapse runs of dashes
        result = result.replacingOccurrences(of: " ", with: "-")
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if result.count > 200 { result = String(result.prefix(200)) }
        if result.isEmpty { result = "untitled" }
        return result
    }
}
