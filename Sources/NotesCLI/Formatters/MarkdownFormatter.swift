import NotesCore
import Foundation

enum MarkdownFormatter {
    static func printEncodable<T: Encodable>(_ value: T, heading: String = "Output") throws {
        let data = try JSONOutputFormatter.encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)

        guard let dictionary = object as? [String: Any] else {
            Swift.print("```json")
            Swift.print(String(decoding: data, as: UTF8.self))
            Swift.print("```")
            return
        }

        Swift.print("# \(heading)\n")
        for key in dictionary.keys.sorted() {
            let value = dictionary[key].map(Self.markdownValue(for:)) ?? "null"
            Swift.print("- **\(key):** \(value)")
        }
    }

    // MARK: - Notes

    static func printNotes(_ notes: [Note]) {
        if notes.isEmpty {
            Swift.print("*No notes found.*")
            return
        }

        Swift.print("# Notes\n")
        for note in notes {
            Swift.print("## \(note.title)")
            Swift.print("- **ID:** \(note.id)")
            Swift.print("- **Folder:** \(note.folderPath)")
            Swift.print("- **Modified:** \(note.modificationDate.iso8601String)")
            Swift.print("")
        }
    }

    static func printNote(_ note: Note) {
        printNote(note, bodyText: note.bodyPlaintext)
    }

    static func printNote(_ note: Note, bodyText: String) {
        Swift.print("# \(note.title)\n")
        Swift.print("| Field | Value |")
        Swift.print("|-------|-------|")
        Swift.print("| ID | \(note.id) |")
        Swift.print("| Folder | \(note.folderPath) |")
        Swift.print("| Created | \(note.creationDate.iso8601String) |")
        Swift.print("| Modified | \(note.modificationDate.iso8601String) |")
        Swift.print("| Locked | \(note.isLocked ? "Yes" : "No") |")
        Swift.print("")
        Swift.print(bodyText)
    }

    // MARK: - Folders

    static func printFolders(_ folders: [Folder]) {
        if folders.isEmpty {
            Swift.print("*No folders found.*")
            return
        }

        Swift.print("# Folders\n")
        Swift.print("| Name | Path | Protected |")
        Swift.print("|------|------|-----------|")
        for folder in folders {
            Swift.print("| \(folder.name) | \(folder.path) | \(folder.isProtected ? "Yes" : "No") |")
        }
    }

    // MARK: - Export

    static func printExportResult(_ result: ExportResult) {
        Swift.print("**Exported** \(result.exported) notes to `\(result.outputPath)`")
        Swift.print("- **Format:** \(result.format)")
        Swift.print("- **Folders:** \(result.folders)")
        if result.skipped > 0 {
            Swift.print("- **Skipped:** \(result.skipped) (conversion errors)")
        }
    }

    private static func markdownValue(for value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return array.map(markdownValue(for:)).joined(separator: ", ")
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().map { key in
                "\(key)=\(markdownValue(for: dictionary[key] as Any))"
            }.joined(separator: ", ")
        }
        return String(describing: value)
    }
}
