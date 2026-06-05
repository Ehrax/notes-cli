import Foundation

enum InlineMarkdownFormatter {
    enum ItalicPolicy {
        case markdown
        case plain
    }

    static func apply(
        to text: String,
        fontWeight: Int32?,
        underlined: Bool,
        strikethrough: Bool,
        italicPolicy: ItalicPolicy = .markdown
    ) -> String {
        guard fontWeight != nil || underlined || strikethrough else { return text }

        var result = text
        if underlined {
            result = wrapMarker(result, marker: "**")
        }

        if let fontWeight {
            switch fontWeight {
            case 1:
                result = wrapMarker(result, marker: "**")
            case 2:
                if italicPolicy == .markdown {
                    result = wrapMarker(result, marker: "*")
                }
            case 3:
                result = wrapMarker(result, marker: italicPolicy == .markdown ? "***" : "**")
            default:
                break
            }
        }

        if strikethrough {
            result = wrapMarker(result, marker: "~~")
        }

        return result
    }

    /// Wrap text with markers while keeping surrounding whitespace outside the markers.
    static func wrapMarker(_ text: String, marker: String) -> String {
        let leading = String(text.prefix(while: \.isWhitespace))
        let trailing = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
        let inner = text.dropFirst(leading.count).dropLast(trailing.count)
        guard !inner.isEmpty else { return text }
        return "\(leading)\(marker)\(inner)\(marker)\(trailing)"
    }
}
