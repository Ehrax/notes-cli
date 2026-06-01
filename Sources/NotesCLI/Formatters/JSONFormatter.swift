import NotesCore
import Foundation

enum JSONOutputFormatter {
    static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    static func print<T: Encodable>(_ value: T) throws {
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NotesError.databaseCorrupted(underlying: NSError(
                domain: "notes-cli", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON output as UTF-8"]
            ))
        }
        Swift.print(json)
    }
}
