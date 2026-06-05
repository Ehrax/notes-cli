import NotesCore
import Foundation

enum OutputFormatter {
    static func print<T: Encodable>(_ value: T, format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(value)
        case .table:
            // For generic Encodable, fall back to JSON
            try JSONOutputFormatter.print(value)
        case .markdown:
            try MarkdownFormatter.printEncodable(value)
        }
    }

    static func printNotes(_ notes: [Note], format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(notes.map(NoteOutput.init))
        case .table:
            TableFormatter.printNotes(notes)
        case .markdown:
            MarkdownFormatter.printNotes(notes)
        }
    }

    static func printNote(_ note: Note, format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(NoteOutput(note: note, body: note.bodyPlaintext))
        case .table:
            TableFormatter.printNote(note)
        case .markdown:
            MarkdownFormatter.printNote(note)
        }
    }

    static func printNote(_ note: Note, bodyText: String, format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(NoteOutput(note: note, body: bodyText))
        case .table:
            TableFormatter.printNote(note, bodyText: bodyText)
        case .markdown:
            MarkdownFormatter.printNote(note, bodyText: bodyText)
        }
    }

    static func printFolders(_ folders: [Folder], format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(folders.map(FolderOutput.init))
        case .table:
            TableFormatter.printFolders(folders)
        case .markdown:
            MarkdownFormatter.printFolders(folders)
        }
    }

    static func printFolderTree(_ folders: [Folder], format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(folders.map(FolderOutput.init))
        case .table:
            TableFormatter.printFolderTree(folders)
        case .markdown:
            MarkdownFormatter.printFolderTree(folders)
        }
    }

    static func printMessage(_ message: String, format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(["message": message])
        case .table:
            Swift.print(message)
        case .markdown:
            Swift.print(message)
        }
    }

    static func printExportResult(_ result: ExportResult, format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(result)
        case .table:
            TableFormatter.printExportResult(result)
        case .markdown:
            MarkdownFormatter.printExportResult(result)
        }
    }

    static func printStringList(_ items: [String], format: OutputFormat) throws {
        switch format {
        case .json:
            try JSONOutputFormatter.print(items)
        case .table:
            for item in items {
                Swift.print(item)
            }
        case .markdown:
            for item in items {
                Swift.print("- \(item)")
            }
        }
    }
}

/// Stable JSON shape for notes. Keeps CLI output independent from internal model storage.
private struct NoteOutput: Encodable {
    let id: String
    let title: String
    let body: String?
    let folderPath: String
    let accountName: String?
    let snippet: String?
    let creationDate: Date
    let modificationDate: Date
    let isLocked: Bool

    init(note: Note) {
        self.init(note: note, body: nil)
    }

    init(note: Note, body: String? = nil) {
        self.id = note.id
        self.title = note.title
        self.body = body
        self.folderPath = note.folderPath
        self.accountName = note.accountName
        self.snippet = note.snippet
        self.creationDate = note.creationDate
        self.modificationDate = note.modificationDate
        self.isLocked = note.isLocked
    }
}

/// Stable JSON shape for folders. There is no notes-cli protected-folder state.
private struct FolderOutput: Encodable {
    let id: String
    let name: String
    let path: String
    let parentPath: String?

    init(folder: Folder) {
        id = folder.id
        name = folder.name
        path = folder.path
        parentPath = folder.parentPath
    }
}
