import Foundation
import NotesCore

/// Mock implementation of NotesServiceProtocol for testing.
public final class MockNotesService: NotesServiceProtocol, @unchecked Sendable {
    public var noteMetadata: [AppleNoteMetadata] = []
    public var notes: [AppleNoteRaw] = []
    public var folders: [AppleFolderRaw] = []
    public var accountNames: [String] = []
    public var defaultAccountName: String?
    public var scopedAccountName: String?
    public var rootFolderPath: String?
    public var available: Bool = true

    public var fetchAccountNamesCalled = false
    public var fetchDefaultAccountNameCalled = false
    public var fetchAllNotesCalled = false
    public var searchNotesCalled = false
    public var fetchAllNoteMetadataCalled = false
    public var fetchNoteCalled = false
    public var createNoteCalled = false
    public var updateNoteCalled = false
    public var deleteNoteCalled = false
    public var moveNoteCalled = false
    public var fetchFoldersCalled = false
    public var createFolderCalled = false
    public var renameFolderCalled = false
    public var deleteFolderCalled = false
    public var moveFolderCalled = false
    public var isAvailableCalled = false

    public var lastFetchedNoteID: String?
    public var fetchedNoteIDs: [String] = []
    public var lastCreatedTitle: String?
    public var lastCreatedBody: String?
    public var lastCreatedFolder: String?
    public var lastUpdatedID: String?
    public var lastUpdatedTitle: String?
    public var lastUpdatedBody: String?
    public var lastDeletedID: String?
    public var lastMovedID: String?
    public var lastMovedFolder: String?
    public var lastSearchQuery: String?
    public var lastSearchLimit: Int?
    public var lastCreatedFolderName: String?
    public var lastCreatedFolderParent: String?
    public var lastRenamedFolderPath: String?
    public var lastRenamedFolderNewName: String?
    public var lastDeletedFolderPath: String?
    public var lastMovedFolderPath: String?
    public var lastMovedFolderParent: String?

    public var errorToThrow: Error?
    public var fetchNoteSequence: [AppleNoteRaw?] = []

    public init() {}

    public func fetchAccountNames() async throws -> [String] {
        fetchAccountNamesCalled = true
        if let error = errorToThrow { throw error }
        return accountNames
    }

    public func fetchDefaultAccountName() async throws -> String? {
        fetchDefaultAccountNameCalled = true
        if let error = errorToThrow { throw error }
        return defaultAccountName
    }

    public func scopedFolderPath(_ folderPath: String) -> String {
        let trimmedFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFolderPath.isEmpty else { return trimmedFolderPath }
        guard
            let scopedAccountName = normalizedScopedAccountName,
            !trimmedFolderPath.hasPrefix(scopedAccountName + "/"),
            trimmedFolderPath != scopedAccountName
        else {
            return trimmedFolderPath
        }
        return scopedAccountName + "/" + trimmedFolderPath
    }

    public func resolvedFolderPath(_ folderPath: String?) -> String {
        if let folderPath {
            let trimmedFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedFolderPath.isEmpty {
                return scopedFolderPath(trimmedFolderPath)
            }
        }

        if let rootFolderPath {
            return scopedFolderPath(rootFolderPath)
        }

        return normalizedScopedAccountName ?? ""
    }

    public func fetchAllNotes() async throws -> [AppleNoteRaw] {
        fetchAllNotesCalled = true
        if let error = errorToThrow { throw error }
        return notes
    }

    public func fetchAllNoteMetadata() async throws -> [AppleNoteMetadata] {
        fetchAllNoteMetadataCalled = true
        if let error = errorToThrow { throw error }
        if !noteMetadata.isEmpty {
            return noteMetadata
        }

        return notes.map {
            AppleNoteMetadata(
                id: $0.id,
                name: $0.name,
                folderName: $0.folderName,
                folderPath: $0.folderPath,
                creationDate: $0.creationDate,
                modificationDate: $0.modificationDate,
                isLocked: $0.isLocked
            )
        }
    }

    public func searchNotes(query: String, limit: Int) async throws -> [AppleNoteRaw] {
        searchNotesCalled = true
        lastSearchQuery = query
        lastSearchLimit = limit
        if let error = errorToThrow { throw error }
        return NoteSearch.rank(notes: notes, query: query, limit: limit)
    }

    public func fetchNote(id: String) async throws -> AppleNoteRaw? {
        fetchNoteCalled = true
        lastFetchedNoteID = id
        fetchedNoteIDs.append(id)
        if let error = errorToThrow { throw error }
        if !fetchNoteSequence.isEmpty {
            return fetchNoteSequence.removeFirst()
        }
        return notes.first { $0.id == id }
    }

    public func createNote(title: String, bodyHTML: String, folderName: String) async throws -> String {
        createNoteCalled = true
        lastCreatedTitle = title
        lastCreatedBody = bodyHTML
        let resolvedFolderName = resolvedFolderPath(folderName)
        lastCreatedFolder = resolvedFolderName
        if let error = errorToThrow { throw error }
        let resolvedFolderComponent = resolvedFolderName.components(separatedBy: "/").last ?? resolvedFolderName
        let newID = "x-coredata://mock/\(UUID().uuidString)"
        let note = AppleNoteRaw(
            id: newID,
            name: title,
            bodyProtobuf: Data(),
            bodyPlaintext: "",
            folderName: resolvedFolderComponent,
            folderPath: resolvedFolderName,
            creationDate: Date(),
            modificationDate: Date(),
            isLocked: false
        )
        notes.append(note)
        return newID
    }

    public func updateNote(id: String, title: String?, bodyHTML: String?) async throws {
        updateNoteCalled = true
        lastUpdatedID = id
        lastUpdatedTitle = title
        lastUpdatedBody = bodyHTML
        if let error = errorToThrow { throw error }
        if let index = notes.firstIndex(where: { $0.id == id }) {
            if let title {
                notes[index].name = title
            }
            if bodyHTML != nil {
                notes[index].bodyProtobuf = Data()
            }
            notes[index].modificationDate = Date()
        }
    }

    public func deleteNote(id: String) async throws {
        deleteNoteCalled = true
        lastDeletedID = id
        if let error = errorToThrow { throw error }
        notes.removeAll { $0.id == id }
    }

    public func moveNote(id: String, toFolder folderName: String) async throws {
        moveNoteCalled = true
        lastMovedID = id
        let resolvedFolderName = resolvedFolderPath(folderName)
        lastMovedFolder = resolvedFolderName
        if let error = errorToThrow { throw error }
        if let index = notes.firstIndex(where: { $0.id == id }) {
            notes[index].folderPath = resolvedFolderName
            notes[index].folderName = resolvedFolderName.components(separatedBy: "/").last ?? resolvedFolderName
            notes[index].modificationDate = Date()
        }
    }

    public func fetchFolders() async throws -> [AppleFolderRaw] {
        fetchFoldersCalled = true
        if let error = errorToThrow { throw error }
        return folders
    }

    public func fetchAttachments(noteID: String) async throws -> [NoteAttachment] {
        if let error = errorToThrow { throw error }
        return []
    }

    public func createFolder(name: String, parentName: String?) async throws {
        createFolderCalled = true
        lastCreatedFolderName = name
        let resolvedParentName = parentName.map { resolvedFolderPath($0) }
        lastCreatedFolderParent = resolvedParentName
        if let error = errorToThrow { throw error }
        let path = resolvedParentName.map { "\($0)/\(name)" } ?? scopedFolderPath(name)
        folders.append(AppleFolderRaw(id: "x-coredata://mock/\(UUID().uuidString)", name: name, path: path, parentPath: resolvedParentName))
    }

    public func renameFolder(path: String, newName: String) async throws {
        renameFolderCalled = true
        lastRenamedFolderPath = resolvedFolderPath(path)
        lastRenamedFolderNewName = newName
        if let error = errorToThrow { throw error }
        if let index = folders.firstIndex(where: { $0.path == lastRenamedFolderPath }) {
            folders[index].name = newName
        }
    }

    public func deleteFolder(path: String) async throws {
        deleteFolderCalled = true
        let resolvedPath = resolvedFolderPath(path)
        lastDeletedFolderPath = resolvedPath
        if let error = errorToThrow { throw error }
        folders.removeAll { $0.path == resolvedPath }
    }

    public func moveFolder(path: String, toParent parentPath: String?) async throws {
        moveFolderCalled = true
        lastMovedFolderPath = resolvedFolderPath(path)
        let resolvedParentName = parentPath.map { resolvedFolderPath($0) }
        lastMovedFolderParent = resolvedParentName
        if let error = errorToThrow { throw error }
    }

    public func isAvailable() async throws -> Bool {
        isAvailableCalled = true
        if let error = errorToThrow { throw error }
        return available
    }

    private var normalizedScopedAccountName: String? {
        let trimmed = (scopedAccountName ?? defaultAccountName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
