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

    // MARK: - Tags

    static func printTags(_ tags: [Tag]) {
        if tags.isEmpty {
            Swift.print("*No tags found.*")
            return
        }

        Swift.print("# Tags\n")
        for tag in tags {
            Swift.print("- \(tag.name)")
        }
    }

    // MARK: - Links

    static func printLinks(_ links: [Link]) {
        if links.isEmpty {
            Swift.print("*No links found.*")
            return
        }

        Swift.print("# Links\n")
        Swift.print("| Source | Target | Created |")
        Swift.print("|--------|--------|---------|")
        for link in links {
            Swift.print("| \(link.sourceNoteID) | \(link.targetNoteID) | \(link.createdAt.iso8601String) |")
        }
    }

    // MARK: - Sync

    static func printSyncResult(_ result: SyncResult) {
        Swift.print("# Sync Result\n")
        Swift.print("| Metric | Count |")
        Swift.print("|--------|-------|")
        Swift.print("| Added | \(result.added) |")
        Swift.print("| Updated | \(result.updated) |")
        Swift.print("| Deleted | \(result.deleted) |")
        Swift.print("| Unchanged | \(result.unchanged) |")

        if !result.errors.isEmpty {
            Swift.print("")
            Swift.print("## Errors\n")
            for error in result.errors {
                let noteID = error.noteID ?? "unknown"
                Swift.print("- \(noteID): \(error.message)")
            }
        }
    }

    // MARK: - History

    static func printHistory(_ actions: [ActionSummary]) {
        if actions.isEmpty {
            Swift.print("*No actions recorded.*")
            return
        }

        Swift.print("# Action History\n")
        Swift.print("| ID | Type | Note | When | Undone |")
        Swift.print("|----|------|------|------|--------|")
        for action in actions {
            let idStr = action.id.map { String($0) } ?? "-"
            Swift.print(
                "| \(idStr) | \(action.type.rawValue) | \(action.noteID) "
                + "| \(action.timestamp.iso8601String) | \(action.undone ? "Yes" : "No") |"
            )
        }
    }

    // MARK: - Undo

    static func printUndoResult(_ result: UndoResult) {
        Swift.print("**Undo:** \(result.description)")
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
