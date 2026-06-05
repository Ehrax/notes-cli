import NotesCore

enum FolderTreeRenderer {
    static func rows(for folders: [Folder]) -> [String] {
        folders.sorted { $0.path < $1.path }.map { folder in
            let depth = folder.path.split(separator: "/").count - 1
            let indent = String(repeating: "  ", count: max(0, depth))
            return "\(indent)\(folder.name)"
        }
    }
}
