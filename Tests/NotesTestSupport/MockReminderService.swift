import Foundation
import NotesCore

/// Mock implementation of ReminderServiceProtocol for testing.
public final class MockReminderService: ReminderServiceProtocol, @unchecked Sendable {
    public var reminders: [ReminderInfo] = []
    public var accessGranted: Bool = true

    public var requestAccessCalled = false
    public var syncCheckboxesCalled = false
    public var completeReminderCalled = false
    public var fetchRemindersCalled = false

    public var lastSyncedNoteID: String?
    public var lastSyncedNoteTitle: String?
    public var lastSyncedCheckboxes: [Checkbox]?
    public var lastCompletedIdentifier: String?
    public var lastFetchedNoteID: String?

    public var errorToThrow: Error?

    public init() {}

    public func requestAccess() async throws -> Bool {
        requestAccessCalled = true
        if let error = errorToThrow { throw error }
        if !accessGranted { throw NotesError.reminderPermissionDenied }
        return accessGranted
    }

    public func syncCheckboxes(noteID: String, noteTitle: String, checkboxes: [Checkbox]) async throws {
        syncCheckboxesCalled = true
        lastSyncedNoteID = noteID
        lastSyncedNoteTitle = noteTitle
        lastSyncedCheckboxes = checkboxes
        if let error = errorToThrow { throw error }
    }

    public func completeReminder(identifier: String) async throws {
        completeReminderCalled = true
        lastCompletedIdentifier = identifier
        if let error = errorToThrow { throw error }
    }

    public func fetchReminders(forNoteID noteID: String) async throws -> [ReminderInfo] {
        fetchRemindersCalled = true
        lastFetchedNoteID = noteID
        if let error = errorToThrow { throw error }
        return reminders.filter { $0.noteID == noteID }
    }
}
