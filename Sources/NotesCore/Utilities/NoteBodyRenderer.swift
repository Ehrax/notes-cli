import Foundation

/// Canonical note-body renderer for read/export/editor display.
public enum NoteBodyRenderer {
    /// Convert a note body to Markdown, falling back to Apple's plaintext when protobuf decoding fails.
    public static func markdown(for body: AppleNoteBody, resolver: any AttachmentResolver) -> String {
        guard !body.protobuf.isEmpty else {
            return body.plaintext
        }
        do {
            let result = try ProtobufToMarkdown.convert(data: body.protobuf, resolver: resolver)
            return result.markdown
        } catch {
            Log.debug(
                "Protobuf conversion failed for note \(body.id), falling back to plaintext: \(error)",
                logger: Log.general
            )
            return body.plaintext
        }
    }
}
