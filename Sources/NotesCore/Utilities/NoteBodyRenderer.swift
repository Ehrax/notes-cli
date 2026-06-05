import Foundation

/// Canonical note-body renderer for read/export/editor display.
public enum NoteBodyRenderer {
    /// Convert a note body to Markdown, falling back to Apple's plaintext when protobuf decoding fails.
    public static func markdown(for note: AppleNoteRaw, resolver: any AttachmentResolver) -> String {
        guard !note.bodyProtobuf.isEmpty else {
            return note.bodyPlaintext
        }
        do {
            let result = try ProtobufToMarkdown.convert(data: note.bodyProtobuf, resolver: resolver)
            return result.markdown
        } catch {
            Log.debug(
                "Protobuf conversion failed for note \(note.id), falling back to plaintext: \(error)",
                logger: Log.general
            )
            return note.bodyPlaintext
        }
    }
}
