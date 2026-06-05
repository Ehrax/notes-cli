import Foundation

/// Exports notes from the live Apple Notes database to files on disk.
public final class ExportService: Sendable {
    private let notes: any NotesServiceProtocol
    private let appleNotesRootURL: URL

    private static let appleNotesRoot =
        "Library/Group Containers/group.com.apple.notes"

    public init(notes: any NotesServiceProtocol, appleNotesRootURL: URL? = nil) {
        self.notes = notes
        self.appleNotesRootURL = appleNotesRootURL ?? Self.defaultAppleNotesRootURL()
    }

    // MARK: - Public

    public func export(
        format: ExportFormat,
        outputDir: String,
        folder: String? = nil,
        ignoreFolders: [String] = [],
        scope: Config.NotesScope = .default
    ) async throws -> ExportResult {
        let rawNotes = try await fetchFiltered(
            folder: folder, ignoreFolders: ignoreFolders, scope: scope
        )

        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        var exported = 0
        var skipped = 0
        var folderPaths = Set<String>()
        var usedPaths = [String: Int]()

        let total = rawNotes.count
        Self.progress("Exporting \(total) notes as \(format.rawValue) → \(outputDir)")

        for (index, rawNote) in rawNotes.enumerated() {
            let note = Note(from: rawNote)
            let counter = "[\(index + 1)/\(total)]"
            do {
                let fileURL = try prepareFileURL(
                    note: note, format: format,
                    outputURL: outputURL, usedPaths: &usedPaths
                )
                let isNewFolder = !folderPaths.contains(note.folderPath)
                folderPaths.insert(note.folderPath)

                if isNewFolder {
                    Self.progress("\(counter) 📂 \(note.folderPath)")
                }

                let content = try await renderContent(
                    rawNote: rawNote, note: note, format: format, outputURL: outputURL
                )
                try content.write(
                    to: fileURL, atomically: true, encoding: .utf8
                )
                exported += 1
                Self.progress("\(counter) ✓ \(fileURL.lastPathComponent)")
            } catch {
                Self.progress("\(counter) ✗ SKIP \(note.title): \(error.localizedDescription)")
                skipped += 1
            }
        }

        return ExportResult(
            exported: exported, skipped: skipped,
            folders: folderPaths.count, format: format.rawValue,
            outputPath: outputDir
        )
    }

    // MARK: - Markdown front-matter

    static func markdownWithFrontmatter(note: Note, body: String) -> String {
        var lines = ["---"]
        let escaped = note.title.replacingOccurrences(
            of: "\"", with: "\\\""
        )
        lines.append("title: \"\(escaped)\"")
        lines.append("created: \(note.creationDate.iso8601String)")
        lines.append("modified: \(note.modificationDate.iso8601String)")
        lines.append("---")
        lines.append(Self.stripRedundantTitle(body, title: note.title))
        return lines.joined(separator: "\n")
    }

    /// Strip duplicate bold line that matches the frontmatter title.
    /// Only removes **bold** text that fuzzy-matches the title — doesn't alter structure.
    static func stripRedundantTitle(_ body: String, title: String) -> String {
        var lines = body.components(separatedBy: "\n")
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !lines.isEmpty else { return body }

        // Check first few non-empty lines for a bold duplicate of the title
        for idx in 0..<min(lines.count, 5) {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Only strip **bold** lines that match the title
            if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
                let boldText = String(line.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
                let clean1 = boldText.trimmingCharacters(
                    in: CharacterSet(charactersIn: "…\u{2026} ")
                )
                let clean2 = trimmedTitle.trimmingCharacters(
                    in: CharacterSet(charactersIn: "…\u{2026} ")
                )
                if clean1.hasPrefix(clean2) || clean2.hasPrefix(clean1) || clean1 == clean2 {
                    lines.remove(at: idx)
                    break
                }
            }
            // Stop after first non-empty, non-heading line
            if !line.hasPrefix("#") { break }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    private func fetchFiltered(
        folder: String?,
        ignoreFolders: [String] = [],
        scope: Config.NotesScope
    ) async throws -> [AppleNoteRaw] {
        var notes = try await self.notes.fetchAllNotes()

        if let folder {
            notes = notes.filter { scope.matchesFolderPath($0.folderPath, filter: folder) }
        }

        if !ignoreFolders.isEmpty {
            notes = notes.filter { note in
                !ignoreFolders.contains { scope.matchesFolderPath(note.folderPath, filter: $0) }
            }
        }

        return notes
    }

    private func prepareFileURL(
        note: Note,
        format: ExportFormat,
        outputURL: URL,
        usedPaths: inout [String: Int]
    ) throws -> URL {
        let fm = FileManager.default
        let folderURL = outputURL.appendingPathComponent(
            note.folderPath, isDirectory: true
        )
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let ext = format.fileExtension
        let datePrefix = Self.datePrefix(from: note.creationDate)
        var baseName = "\(datePrefix)-\(note.title.exportFilename)"
        while baseName.contains("--") { baseName = baseName.replacingOccurrences(of: "--", with: "-") }
        let key = "\(note.folderPath)/\(baseName)"
        let count = usedPaths[key, default: 0] + 1
        usedPaths[key] = count
        let fileName = count == 1
            ? "\(baseName).\(ext)"
            : "\(baseName)-\(count).\(ext)"
        return folderURL.appendingPathComponent(fileName)
    }

    private static func datePrefix(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func renderContent(
        rawNote: AppleNoteRaw, note: Note, format: ExportFormat, outputURL: URL
    ) async throws -> String {
        let folderURL = outputURL.appendingPathComponent(note.folderPath, isDirectory: true)

        let body = try await notes.renderMarkdownBody(for: rawNote)
        let bodyWithAttachments = try await resolveAttachments(
            noteID: note.id, body: body, folderURL: folderURL
        )

        switch format {
        case .json:
            return try Self.jsonContent(note: note, body: bodyWithAttachments)
        case .md:
            return Self.markdownWithFrontmatter(
                note: note, body: bodyWithAttachments
            )
        }
    }

    static func jsonContent(note: Note, body: String) throws -> String {
        let payload = ExportedNote(
            id: note.id,
            title: note.title,
            body: body,
            folderPath: note.folderPath,
            creationDate: note.creationDate,
            modificationDate: note.modificationDate
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Attachment resolution

    /// Resolve attachment placeholders in the note body, copy image files to assets/.
    /// Replaces `![[attachment:UUID:UTI]]` with `![[assets/filename.ext]]`.
    private func resolveAttachments(
        noteID: String, body: String, folderURL: URL
    ) async throws -> String {
        let attachments = try await notes.fetchAttachments(noteID: noteID)
        guard !attachments.isEmpty else { return body }

        let assetsURL = folderURL.appendingPathComponent("assets", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: assetsURL.path) {
            try fm.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        }

        var result = body

        for attachment in attachments {
            let placeholder = "![[attachment:\(attachment.id):\(attachment.typeUTI ?? "")]]"
            guard result.contains(placeholder) else { continue }

            guard let filename = attachment.filename, !filename.isEmpty else {
                result = result.replacingOccurrences(of: placeholder, with: "<!-- missing attachment -->")
                continue
            }

            let sourceURL = appleNotesRootURL.appendingPathComponent(attachment.relativePath)
            let assetFilename = Self.assetFilename(for: attachment, originalFilename: filename)
            let destURL = assetsURL.appendingPathComponent(assetFilename)

            do {
                if !fm.fileExists(atPath: destURL.path) {
                    try fm.copyItem(at: sourceURL, to: destURL)
                }
                result = result.replacingOccurrences(of: placeholder, with: "![[assets/\(assetFilename)]]")
            } catch {
                Self.progress("Warning: could not copy attachment \(filename): \(error.localizedDescription)")
                result = result.replacingOccurrences(of: placeholder, with: "<!-- missing attachment: \(filename) -->")
            }
        }

        return result
    }

    private static func defaultAppleNotesRootURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: "\(home)/\(Self.appleNotesRoot)", isDirectory: true)
    }

    private static func assetFilename(for attachment: NoteAttachment, originalFilename: String) -> String {
        "\(attachment.id.fileSafe)-\(originalFilename.fileSafe)"
    }

    private static func progress(_ message: String) {
        fputs(message + "\n", stderr)
    }
}

/// JSON export shape for a single note (stable public contract).
private struct ExportedNote: Encodable {
    let id: String
    let title: String
    let body: String
    let folderPath: String
    let creationDate: Date
    let modificationDate: Date
}
