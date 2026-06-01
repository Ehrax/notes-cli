import Foundation

/// Protocol for managing reminders that mirror note checkboxes.
public protocol ReminderServiceProtocol: Sendable {
    func requestAccess() async throws -> Bool
    func syncCheckboxes(noteID: String, noteTitle: String, checkboxes: [Checkbox]) async throws
    func completeReminder(identifier: String) async throws
    func fetchReminders(forNoteID noteID: String) async throws -> [ReminderInfo]
}
