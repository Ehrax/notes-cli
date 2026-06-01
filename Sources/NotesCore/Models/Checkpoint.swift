import Foundation

/// A snapshot of a note's state, used for undo/redo operations.
public struct Checkpoint: Codable, Sendable, Equatable {
    /// The unique identifier of the note.
    public var noteID: String

    /// The title of the note at the time of the snapshot.
    public var title: String

    /// The raw gzipped protobuf body at the time of the snapshot.
    public var bodyProtobuf: Data

    /// The plaintext body of the note at the time of the snapshot.
    public var bodyPlaintext: String

    /// The folder path the note resided in at the time of the snapshot.
    public var folderPath: String

    public init(noteID: String, title: String, bodyProtobuf: Data, bodyPlaintext: String, folderPath: String) {
        self.noteID = noteID
        self.title = title
        self.bodyProtobuf = bodyProtobuf
        self.bodyPlaintext = bodyPlaintext
        self.folderPath = folderPath
    }

    public init(from note: Note) {
        self.init(
            noteID: note.id,
            title: note.title,
            bodyProtobuf: note.bodyProtobuf,
            bodyPlaintext: note.bodyPlaintext,
            folderPath: note.folderPath
        )
    }
}
