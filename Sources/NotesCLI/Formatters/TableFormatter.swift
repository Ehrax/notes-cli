import NotesCore
import Foundation

enum TableFormatter {
    // MARK: - Notes

    static func printNotes(_ notes: [Note]) {
        if notes.isEmpty {
            Swift.print("No notes found.")
            return
        }

        let headers = ["ID", "Title", "Folder", "Modified"]
        let rows: [[String]] = notes.map { note in
            [
                truncate(note.id, max: 20),
                truncate(note.title, max: 40),
                truncate(note.folderPath, max: 20),
                note.modificationDate.relativeString,
            ]
        }
        printTable(headers: headers, rows: rows)
    }

    static func printNote(_ note: Note) {
        printNote(note, bodyText: note.bodyPlaintext)
    }

    static func printNote(_ note: Note, bodyText: String) {
        Swift.print("ID:       \(note.id)")
        Swift.print("Title:    \(note.title)")
        Swift.print("Folder:   \(note.folderPath)")
        Swift.print("Created:  \(note.creationDate.iso8601String)")
        Swift.print("Modified: \(note.modificationDate.iso8601String)")
        Swift.print("Locked:   \(note.isLocked ? "Yes" : "No")")
        Swift.print("")
        Swift.print(bodyText)
    }

    // MARK: - Folders

    static func printFolders(_ folders: [Folder]) {
        if folders.isEmpty {
            Swift.print("No folders found.")
            return
        }

        let headers = ["ID", "Name", "Path", "Protected"]
        let rows: [[String]] = folders.map { folder in
            [
                truncate(folder.id, max: 20),
                folder.name,
                folder.path,
                folder.isProtected ? "Yes" : "No",
            ]
        }
        printTable(headers: headers, rows: rows)
    }

    // MARK: - Tags

    static func printTags(_ tags: [Tag]) {
        if tags.isEmpty {
            Swift.print("No tags found.")
            return
        }

        let headers = ["ID", "Name"]
        let rows: [[String]] = tags.map { tag in
            [
                tag.id.map { String($0) } ?? "-",
                tag.name,
            ]
        }
        printTable(headers: headers, rows: rows)
    }

    // MARK: - Links

    static func printLinks(_ links: [Link]) {
        if links.isEmpty {
            Swift.print("No links found.")
            return
        }

        let headers = ["Source", "Target", "Created"]
        let rows: [[String]] = links.map { link in
            [
                truncate(link.sourceNoteID, max: 20),
                truncate(link.targetNoteID, max: 20),
                link.createdAt.relativeString,
            ]
        }
        printTable(headers: headers, rows: rows)
    }

    // MARK: - Sync

    static func printSyncResult(_ result: SyncResult) {
        Swift.print("Sync complete:")
        Swift.print("  Added:     \(result.added)")
        Swift.print("  Updated:   \(result.updated)")
        Swift.print("  Deleted:   \(result.deleted)")
        Swift.print("  Unchanged: \(result.unchanged)")
        if !result.errors.isEmpty {
            Swift.print("  Errors:    \(result.errors.count)")
            for err in result.errors {
                let noteInfo = err.noteID.map { " (note: \($0))" } ?? ""
                Swift.print("    - \(err.message)\(noteInfo)")
            }
        }
    }

    // MARK: - History

    static func printHistory(_ actions: [ActionSummary]) {
        if actions.isEmpty {
            Swift.print("No actions recorded.")
            return
        }

        let headers = ["ID", "Type", "Note ID", "When", "Undone"]
        let rows: [[String]] = actions.map { action in
            [
                action.id.map { String($0) } ?? "-",
                action.type.rawValue,
                truncate(action.noteID, max: 20),
                action.timestamp.relativeString,
                action.undone ? "Yes" : "No",
            ]
        }
        printTable(headers: headers, rows: rows)
    }

    // MARK: - Undo

    static func printUndoResult(_ result: UndoResult) {
        Swift.print(result.description)
    }

    // MARK: - Export

    static func printExportResult(_ result: ExportResult) {
        Swift.print("Exported \(result.exported) notes to \(result.outputPath)")
        Swift.print("  Format: \(result.format)")
        Swift.print("  Folders: \(result.folders)")
        if result.skipped > 0 {
            Swift.print("  Skipped: \(result.skipped) (conversion errors)")
        }
    }

    // MARK: - Table rendering

    private static func printTable(headers: [String], rows: [[String]]) {
        guard !headers.isEmpty else { return }

        // Calculate column widths
        var widths = headers.map(\.count)
        for row in rows {
            for (idx, cell) in row.enumerated() where idx < widths.count {
                widths[idx] = max(widths[idx], cell.count)
            }
        }

        // Print header
        let headerLine = zip(headers, widths).map { header, width in
            header.padding(toLength: width, withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
        Swift.print(headerLine)

        // Print separator
        let separator = widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
        Swift.print(separator)

        // Print rows
        for row in rows {
            let line = zip(row, widths).map { cell, width in
                cell.padding(toLength: width, withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            Swift.print(line)
        }
    }

    private static func truncate(_ string: String, max: Int) -> String {
        if string.count <= max { return string }
        return String(string.prefix(max - 3)) + "..."
    }
}
