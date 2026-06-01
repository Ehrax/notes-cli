import Foundation
import NotesCore

/// Creates a real DatabaseService backed by an in-memory SQLite database.
public func makeRealDatabase() throws -> DatabaseService {
    try DatabaseService(path: ":memory:")
}

/// Factory for creating sample Note instances in tests.
public func makeSampleNote(
    id: String = "note-1",
    title: String = "Test Note",
    bodyProtobuf: Data = Data(),
    bodyPlaintext: String = "Hello",
    folderPath: String = "Notes",
    syncedAt: Date = Date()
) -> Note {
    Note(
        id: id,
        title: title,
        bodyProtobuf: bodyProtobuf,
        bodyPlaintext: bodyPlaintext,
        folderPath: folderPath,
        syncedAt: syncedAt
    )
}

/// Factory for creating sample AppleNoteRaw instances in tests.
public func makeSampleAppleNote(
    id: String = "note-1",
    name: String = "Test Note",
    bodyProtobuf: Data = Data(),
    bodyPlaintext: String = "Hello",
    folder: String = "Notes",
    creationDate: Date = Date(),
    modificationDate: Date = Date(),
    isLocked: Bool = false
) -> AppleNoteRaw {
    let folderName = folder.components(separatedBy: "/").last ?? folder
    return AppleNoteRaw(
        id: id,
        name: name,
        bodyProtobuf: bodyProtobuf,
        bodyPlaintext: bodyPlaintext,
        folderName: folderName,
        folderPath: folder,
        creationDate: creationDate,
        modificationDate: modificationDate,
        isLocked: isLocked
    )
}

/// Creates a temporary directory for tests. Caller must call `removeTempDirectory` to clean up.
public func makeTempDirectory(prefix: String = "notes-cli-test") throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
}

/// Removes a temporary directory created by `makeTempDirectory`.
public func removeTempDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}
