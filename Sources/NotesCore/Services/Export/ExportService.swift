import Foundation

/// Exports notes from the live Apple Notes database to files on disk.
public final class ExportService: Sendable {
    private let notes: any NotesServiceProtocol
    private let resolver: any AttachmentResolver

    private static let appleNotesRoot =
        "Library/Group Containers/group.com.apple.notes"

    public init(notes: any NotesServiceProtocol, resolver: any AttachmentResolver) {
        self.notes = notes
        self.resolver = resolver
    }

    // MARK: - Public

    public func export(
        format: ExportFormat,
        outputDir: String,
        folder: String? = nil,
        ignoreFolders: [String] = []
    ) async throws -> ExportResult {
        let notes = try await fetchFiltered(
            folder: folder, ignoreFolders: ignoreFolders
        )

        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        var exported = 0
        var skipped = 0
        var folderPaths = Set<String>()
        var usedPaths = [String: Int]()

        let total = notes.count
        Self.progress("Exporting \(total) notes as \(format.rawValue) → \(outputDir)")

        for (index, note) in notes.enumerated() {
            let counter = "[\(index + 1)/\(total)]"
            var exportNote = note
            exportNote.folderPath = Self.fixFolderPath(note.folderPath)
            do {
                let fileURL = try prepareFileURL(
                    note: exportNote, format: format,
                    outputURL: outputURL, usedPaths: &usedPaths
                )
                let isNewFolder = !folderPaths.contains(exportNote.folderPath)
                folderPaths.insert(exportNote.folderPath)

                if isNewFolder {
                    Self.progress("\(counter) 📂 \(exportNote.folderPath)")
                }

                let content = try await renderContent(
                    note: exportNote, format: format, outputURL: outputURL
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

    static func markdownWithFrontmatter(
        note: Note, tags: [String], body: String
    ) -> String {
        var lines = ["---"]
        let escaped = note.title.replacingOccurrences(
            of: "\"", with: "\\\""
        )
        lines.append("title: \"\(escaped)\"")
        lines.append("created: \(note.creationDate.iso8601String)")
        lines.append("modified: \(note.modificationDate.iso8601String)")
        if !tags.isEmpty {
            let tagList = tags.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("tags: [\(tagList)]")
        }
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
        ignoreFolders: [String] = []
    ) async throws -> [Note] {
        var notes = try await self.notes.fetchAllNotes().map { Note(from: $0) }

        if let folder {
            notes = notes.filter { $0.folderPath.contains(folder) }
        }

        if !ignoreFolders.isEmpty {
            notes = notes.filter { note in
                !ignoreFolders.contains { note.folderPath.contains($0) }
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

    /// Ensure space between emoji and text in each folder path component.
    /// Apple Notes stores "👨‍💻ehrax.dev" but we want "👨‍💻 ehrax.dev".
    static func fixFolderPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                var chars = Array(component)
                // Find where emoji ends and text begins, insert space if missing
                guard chars.count >= 2 else { return String(component) }
                for idx in 0..<(chars.count - 1) {
                    let curr = chars[idx]
                    let next = chars[idx + 1]
                    if curr.isEmoji && !next.isWhitespace && !next.isEmoji {
                        chars.insert(" ", at: idx + 1)
                        break
                    }
                }
                return String(chars)
            }
            .joined(separator: "/")
    }

    private static func datePrefix(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func renderContent(
        note: Note, format: ExportFormat, outputURL: URL
    ) async throws -> String {
        let folderURL = outputURL.appendingPathComponent(note.folderPath, isDirectory: true)

        // Convert protobuf → markdown, falling back to plaintext on failure
        let body: String
        if !note.bodyProtobuf.isEmpty {
            do {
                let result = try ProtobufToMarkdown.convert(data: note.bodyProtobuf, resolver: resolver)
                body = result.markdown
            } catch {
                Log.debug(
                    "Protobuf conversion failed for \(note.id), falling back to plaintext: \(error)",
                    logger: Log.general
                )
                body = note.bodyPlaintext
            }
        } else {
            body = note.bodyPlaintext
        }

        let bodyWithAttachments = try await resolveAttachments(
            noteID: note.id, body: body, folderURL: folderURL
        )

        switch format {
        case .json:
            return try Self.jsonContent(note: note, body: bodyWithAttachments)
        case .md:
            return Self.markdownWithFrontmatter(
                note: note, tags: [], body: bodyWithAttachments
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

        let notesRoot = appleNotesRootPath()
        var result = body

        for attachment in attachments {
            let placeholder = "![[attachment:\(attachment.id):\(attachment.typeUTI ?? "")]]"
            guard result.contains(placeholder) else { continue }

            guard let filename = attachment.filename, !filename.isEmpty else {
                result = result.replacingOccurrences(of: placeholder, with: "<!-- missing attachment -->")
                continue
            }

            let sourcePath = "\(notesRoot)/\(attachment.relativePath)"
            let destURL = assetsURL.appendingPathComponent(filename)

            do {
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(atPath: sourcePath, toPath: destURL.path)
                result = result.replacingOccurrences(of: placeholder, with: "![[assets/\(filename)]]")
            } catch {
                Self.progress("Warning: could not copy attachment \(filename): \(error.localizedDescription)")
                result = result.replacingOccurrences(of: placeholder, with: "<!-- missing attachment: \(filename) -->")
            }
        }

        return result
    }

    private func appleNotesRootPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/\(Self.appleNotesRoot)"
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
