import Foundation

public enum Gzip {
    // swiftlint:disable:next cyclomatic_complexity
    public static func decompress(_ data: Data) throws -> Data {
        guard data.count > 18 else {
            throw NotesError.encodingFailure(reason: "Gzip data too short")
        }
        guard data[0] == 0x1F && data[1] == 0x8B else {
            throw NotesError.encodingFailure(reason: "Not a gzip stream")
        }

        let flags = data[3]
        var headerEnd = 10

        if flags & 0x04 != 0 {
            guard data.count > headerEnd + 2 else {
                throw NotesError.encodingFailure(reason: "Truncated FEXTRA")
            }
            headerEnd += 2 + (Int(data[headerEnd]) | (Int(data[headerEnd + 1]) << 8))
        }
        if flags & 0x08 != 0 {
            while headerEnd < data.count && data[headerEnd] != 0 { headerEnd += 1 }
            headerEnd += 1
        }
        if flags & 0x10 != 0 {
            while headerEnd < data.count && data[headerEnd] != 0 { headerEnd += 1 }
            headerEnd += 1
        }
        if flags & 0x02 != 0 { headerEnd += 2 }

        guard data.count > headerEnd + 8 else {
            throw NotesError.encodingFailure(reason: "Truncated gzip payload")
        }
        let deflateData = data.subdata(in: headerEnd ..< (data.count - 8))

        do {
            return try (deflateData as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw NotesError.encodingFailure(reason: "Gzip decompression failed: \(error.localizedDescription)")
        }
    }
}
