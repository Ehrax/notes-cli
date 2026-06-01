@preconcurrency import EventKit
import Foundation

/// Manages reminders that mirror checkboxes from Apple Notes via EventKit.
@MainActor
public final class ReminderService: ReminderServiceProtocol, @unchecked Sendable {

    private let store: EKEventStore
    private let listName = "NotesCLI"
    private let reminderNotePrefix = "notes-cli:noteID="
    private let reminderKeyPrefix = ";checkboxKeyB64="
    private let legacyReminderKeyPrefix = ";checkboxKey="

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    // MARK: - ReminderServiceProtocol

    public func requestAccess() async throws -> Bool {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }
        if !granted {
            throw NotesError.reminderPermissionDenied
        }
        return granted
    }

    public func syncCheckboxes(noteID: String, noteTitle: String, checkboxes: [Checkbox]) async throws {
        try ensureAuthorized()
        let calendar = try findOrCreateNotesCLIList()

        // Fetch existing reminders for this note
        let existing = try await fetchEKReminders(forNoteID: noteID)
        var existingByKey: [String: EKReminder] = [:]
        var existingByTitle: [String: [EKReminder]] = [:]
        for reminder in existing {
            if let key = reminderCheckboxKey(for: reminder) {
                existingByKey[key] = reminder
            }
            existingByTitle[reminder.title ?? "", default: []].append(reminder)
        }

        for (key, checkbox) in keyedCheckboxes(checkboxes) {
            let reminderTitle = "\(noteTitle): \(checkbox.text)"

            if let existingReminder = Self.consumeExistingReminder(
                forKey: key,
                reminderTitle: reminderTitle,
                existingByKey: &existingByKey,
                existingByTitle: &existingByTitle
            )
            {
                // Update existing reminder
                existingReminder.title = reminderTitle
                existingReminder.isCompleted = checkbox.isChecked
                if let dueDate = checkbox.dueDate {
                    existingReminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day],
                        from: dueDate
                    )
                } else {
                    existingReminder.dueDateComponents = nil
                }
                existingReminder.notes = reminderNotes(noteID: noteID, checkboxKey: key)
                try store.save(existingReminder, commit: false)
            } else {
                // Create new reminder
                let reminder = EKReminder(eventStore: store)
                reminder.title = reminderTitle
                reminder.calendar = calendar
                reminder.isCompleted = checkbox.isChecked
                reminder.notes = reminderNotes(noteID: noteID, checkboxKey: key)

                if let dueDate = checkbox.dueDate {
                    reminder.dueDateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day],
                        from: dueDate
                    )
                }
                try store.save(reminder, commit: false)
            }
        }

        // Remove reminders for checkboxes that no longer exist
        let staleReminders = Self.deduplicatedReminders(
            Array(existingByKey.values) + existingByTitle.values.flatMap { $0 }
        )
        for staleReminder in staleReminders {
            try store.remove(staleReminder, commit: false)
        }

        try store.commit()
    }

    public func completeReminder(identifier: String) async throws {
        try ensureAuthorized()
        guard let item = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }
        item.isCompleted = true
        try store.save(item, commit: true)
    }

    public func fetchReminders(forNoteID noteID: String) async throws -> [ReminderInfo] {
        try ensureAuthorized()

        let ekReminders = try await fetchEKReminders(forNoteID: noteID)
        return ekReminders.map { reminder in
            ReminderInfo(
                identifier: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                isCompleted: reminder.isCompleted,
                dueDate: reminder.dueDateComponents?.date,
                noteID: noteID
            )
        }
    }

    // MARK: - Private

    private func ensureAuthorized() throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        let isAuthorized: Bool
        if #available(macOS 14.0, *) {
            isAuthorized = status == .authorized || status == .fullAccess
        } else {
            isAuthorized = status == .authorized
        }
        guard isAuthorized else {
            throw NotesError.reminderPermissionDenied
        }
    }

    private func findOrCreateNotesCLIList() throws -> EKCalendar {
        // Look for existing NotesCLI list
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == listName }) {
            return existing
        }

        // Create a new NotesCLI reminder list
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = listName

        // Use the default reminder source
        if let defaultSource = store.defaultCalendarForNewReminders()?.source {
            calendar.source = defaultSource
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else {
            calendar.source = store.sources.first
        }

        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func fetchEKReminders(forNoteID noteID: String) async throws -> [EKReminder] {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)

        return try await withCheckedThrowingContinuation { continuation in
            self.store.fetchReminders(matching: predicate) { reminders in
                nonisolated(unsafe) let filtered = (reminders ?? []).filter { reminder in
                    if let metadata = Self.reminderMetadata(for: reminder.notes) {
                        return metadata.noteID == noteID
                    }
                    if let legacyNoteID = Self.legacyReminderNoteID(for: reminder.notes) {
                        return legacyNoteID == noteID
                    }
                    return false
                }
                continuation.resume(returning: filtered)
            }
        }
    }

    private func keyedCheckboxes(_ checkboxes: [Checkbox]) -> [(String, Checkbox)] {
        var occurrenceCounts: [String: Int] = [:]
        return checkboxes.map { checkbox in
            let index = occurrenceCounts[checkbox.text, default: 0]
            occurrenceCounts[checkbox.text] = index + 1
            return ("\(checkbox.text)#\(index)", checkbox)
        }
    }

    private func reminderNotes(noteID: String, checkboxKey: String) -> String {
        let encodedKey = Data(checkboxKey.utf8).base64EncodedString()
        return "\(reminderNotePrefix)\(noteID)\(reminderKeyPrefix)\(encodedKey)"
    }

    private func reminderCheckboxKey(for reminder: EKReminder) -> String? {
        Self.reminderMetadata(for: reminder.notes)?.checkboxKey
    }

    nonisolated static func consumeExistingReminder(
        forKey key: String,
        reminderTitle: String,
        existingByKey: inout [String: EKReminder],
        existingByTitle: inout [String: [EKReminder]]
    ) -> EKReminder? {
        if let reminder = existingByKey.removeValue(forKey: key) {
            removeReminder(reminder, from: &existingByTitle)
            return reminder
        }

        guard let reminder = existingByTitle[reminderTitle]?.first else {
            return nil
        }

        removeReminder(reminder, from: &existingByTitle)

        if let previousKey = checkboxKey(for: reminder) {
            existingByKey.removeValue(forKey: previousKey)
        }

        return reminder
    }

    private nonisolated static func checkboxKey(for reminder: EKReminder) -> String? {
        reminderMetadata(for: reminder.notes)?.checkboxKey
    }

    nonisolated static func reminderMetadata(for notes: String?) -> (noteID: String, checkboxKey: String?)? {
        guard let notes, let noteRange = notes.range(of: "notes-cli:noteID=") else {
            return nil
        }

        let payload = notes[noteRange.upperBound...]
        let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let noteIDPart = parts.first, !noteIDPart.isEmpty else {
            return nil
        }

        let checkboxKey: String?
        if parts.count == 2, parts[1].hasPrefix("checkboxKeyB64=") {
            let encodedValue = String(parts[1].dropFirst("checkboxKeyB64=".count))
            if let data = Data(base64Encoded: encodedValue), let decodedValue = String(data: data, encoding: .utf8) {
                checkboxKey = decodedValue
            } else {
                checkboxKey = nil
            }
        } else if parts.count == 2, parts[1].hasPrefix("checkboxKey=") {
            checkboxKey = String(parts[1].dropFirst("checkboxKey=".count))
        } else {
            checkboxKey = nil
        }

        return (noteID: String(noteIDPart), checkboxKey: checkboxKey)
    }

    nonisolated static func legacyReminderNoteID(for notes: String?) -> String? {
        guard let notes, let range = notes.range(of: "noteID:") else {
            return nil
        }

        let suffix = notes[range.upperBound...]
        let noteID = suffix.prefix { character in
            !character.isWhitespace && character != ";"
        }

        guard !noteID.isEmpty else {
            return nil
        }

        return String(noteID)
    }

    nonisolated static func deduplicatedReminders(_ reminders: [EKReminder]) -> [EKReminder] {
        var seenIdentifiers: Set<String> = []
        var deduplicated: [EKReminder] = []

        for reminder in reminders {
            let identifier = reminder.calendarItemIdentifier
            if seenIdentifiers.insert(identifier).inserted {
                deduplicated.append(reminder)
            }
        }

        return deduplicated
    }

    private nonisolated static func removeReminder(
        _ reminder: EKReminder,
        from remindersByTitle: inout [String: [EKReminder]]
    ) {
        for title in remindersByTitle.keys {
            remindersByTitle[title] = remindersByTitle[title]?.filter {
                $0.calendarItemIdentifier != reminder.calendarItemIdentifier
            }
        }
    }
}
