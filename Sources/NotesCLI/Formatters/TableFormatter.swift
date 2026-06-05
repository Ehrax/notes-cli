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

        let headers = ["ID", "Name", "Path"]
        let rows: [[String]] = folders.map { folder in
            [
                truncate(folder.id, max: 20),
                folder.name,
                folder.path,
            ]
        }
        printTable(headers: headers, rows: rows)
    }

    static func printFolderTree(_ folders: [Folder]) {
        if folders.isEmpty {
            Swift.print("No folders found.")
            return
        }

        for folder in FolderTreeRenderer.rows(for: folders) {
            Swift.print(folder)
        }
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
