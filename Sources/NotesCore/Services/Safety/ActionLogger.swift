import Foundation

/// Helper that creates ActionRecord entries with proper JSON encoding of Checkpoints.
public struct ActionLogger: Sendable {
    private static func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .sortedKeys
        return enc
    }

    private static func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    /// Creates an ActionRecord with JSON-encoded before/after checkpoint states.
    public static func makeRecord(
        type: ActionType,
        noteID: String,
        before: Checkpoint?,
        after: Checkpoint?,
        metadata: [String: String]?
    ) throws -> ActionRecord {
        let encoder = Self.makeEncoder()

        let beforeJSON: String? = try before.map { checkpoint in
            let data = try encoder.encode(checkpoint)
            guard let json = String(data: data, encoding: .utf8) else {
                throw NotesError.encodingFailure(reason: "Failed to encode before checkpoint")
            }
            return json
        }

        let afterJSON: String? = try after.map { checkpoint in
            let data = try encoder.encode(checkpoint)
            guard let json = String(data: data, encoding: .utf8) else {
                throw NotesError.encodingFailure(reason: "Failed to encode after checkpoint")
            }
            return json
        }

        let metadataJSON: String? = try metadata.map { meta in
            let data = try encoder.encode(meta)
            guard let json = String(data: data, encoding: .utf8) else {
                throw NotesError.encodingFailure(reason: "Failed to encode metadata")
            }
            return json
        }

        return ActionRecord(
            actionType: type,
            noteID: noteID,
            timestamp: Date(),
            beforeState: beforeJSON,
            afterState: afterJSON,
            metadata: metadataJSON,
            undone: false
        )
    }

    /// Decodes a Checkpoint from a JSON string stored in an ActionRecord.
    public static func decodeCheckpoint(from json: String) throws -> Checkpoint {
        guard let data = json.data(using: .utf8) else {
            throw NotesError.encodingFailure(reason: "Invalid checkpoint JSON")
        }
        return try Self.makeDecoder().decode(Checkpoint.self, from: data)
    }
}
