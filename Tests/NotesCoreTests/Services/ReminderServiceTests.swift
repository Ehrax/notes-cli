import Foundation
@preconcurrency import EventKit
import Testing
@testable import NotesCore
import NotesTestSupport

@Suite("CheckboxParser Tests")
struct CheckboxParserTests {

    @Test("Parse unchecked markdown checkbox")
    func parseUncheckedCheckbox() {
        let result = CheckboxParser.parse("- [ ] Buy groceries")
        #expect(result.count == 1)
        #expect(result[0].text == "Buy groceries")
        #expect(result[0].isChecked == false)
        #expect(result[0].dueDate == nil)
    }

    @Test("Parse checked markdown checkbox")
    func parseCheckedCheckbox() {
        let result = CheckboxParser.parse("- [x] Done task")
        #expect(result.count == 1)
        #expect(result[0].text == "Done task")
        #expect(result[0].isChecked == true)
    }

    @Test("Parse uppercase X as checked")
    func parseUppercaseX() {
        let result = CheckboxParser.parse("- [X] Also done")
        #expect(result.count == 1)
        #expect(result[0].isChecked == true)
    }

    @Test("Parse checkbox with due date")
    func parseCheckboxWithDueDate() {
        let result = CheckboxParser.parse("- [ ] Submit report due:2026-03-15")
        #expect(result.count == 1)
        #expect(result[0].text == "Submit report")
        #expect(result[0].isChecked == false)
        #expect(result[0].dueDate != nil)

        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: result[0].dueDate!)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    @Test("Parse multiple checkboxes from multiline text")
    func parseMultipleCheckboxes() {
        let text = """
        # My Tasks
        - [ ] First task
        - [x] Second task
        - [ ] Third task due:2026-04-01
        Some other text
        """
        let result = CheckboxParser.parse(text)
        #expect(result.count == 3)
        #expect(result[0].text == "First task")
        #expect(result[0].isChecked == false)
        #expect(result[1].text == "Second task")
        #expect(result[1].isChecked == true)
        #expect(result[2].text == "Third task")
        #expect(result[2].dueDate != nil)
    }

    @Test("Parse empty text returns empty array")
    func parseEmptyText() {
        let result = CheckboxParser.parse("")
        #expect(result.isEmpty)
    }

    @Test("Ignore non-checkbox lines")
    func ignoreNonCheckboxLines() {
        let text = """
        # Heading
        Some paragraph text.
        - Regular list item
        Another line.
        """
        let result = CheckboxParser.parse(text)
        #expect(result.isEmpty)
    }

    @Test("Parse HTML checked checkbox")
    func parseHTMLCheckedCheckbox() {
        let html = """
        <ul><li class="checked">Buy milk</li></ul>
        """
        let result = CheckboxParser.parse(html)
        #expect(result.count == 1)
        #expect(result[0].text == "Buy milk")
        #expect(result[0].isChecked == true)
    }

    @Test("Parse HTML unchecked checkbox")
    func parseHTMLUncheckedCheckbox() {
        let html = """
        <ul><li class="unchecked">Write docs</li></ul>
        """
        let result = CheckboxParser.parse(html)
        #expect(result.count == 1)
        #expect(result[0].text == "Write docs")
        #expect(result[0].isChecked == false)
    }

    @Test("Parse HTML checkbox with due date")
    func parseHTMLCheckboxWithDueDate() {
        let html = """
        <ul><li class="todo">Deploy app due:2026-06-01</li></ul>
        """
        let result = CheckboxParser.parse(html)
        #expect(result.count == 1)
        #expect(result[0].text == "Deploy app")
        #expect(result[0].dueDate != nil)
    }

    @Test("Ignore HTML list items without checkbox class")
    func ignoreNonCheckboxHTMLItems() {
        let html = """
        <ul><li class="normal">Just a list item</li></ul>
        """
        let result = CheckboxParser.parse(html)
        #expect(result.isEmpty)
    }

    @Test("Parse mixed markdown and HTML does not duplicate")
    func parseMixedContent() {
        // Markdown only — no HTML-like checkbox classes
        let text = """
        - [ ] Markdown task
        - [x] Done markdown
        """
        let result = CheckboxParser.parse(text)
        #expect(result.count == 2)
    }

    @Test("Parse markdown checkboxes when HTML list markup is unrelated")
    func parseMarkdownWhenHTMLListIsUnrelated() {
        let text = """
        Intro <li>not a checkbox</li>
        - [ ] Markdown task
        - [x] Done markdown
        """
        let result = CheckboxParser.parse(text)
        #expect(result.count == 2)
        #expect(result[0].text == "Markdown task")
        #expect(result[1].isChecked == true)
    }

    @Test("Parse duplicate checkbox text preserves each item")
    func parseDuplicateCheckboxText() {
        let text = """
        - [ ] Repeat task
        - [ ] Repeat task
        - [x] Repeat task
        """
        let result = CheckboxParser.parse(text)
        #expect(result.count == 3)
    }
}

@Suite("MockReminderService Tests")
struct MockReminderServiceTests {

    @Test("Mock tracks requestAccess call")
    func mockRequestAccess() async throws {
        let mock = MockReminderService()
        let granted = try await mock.requestAccess()
        #expect(granted == true)
        #expect(mock.requestAccessCalled == true)
    }

    @Test("Mock throws on permission denied")
    func mockPermissionDenied() async {
        let mock = MockReminderService()
        mock.accessGranted = false
        await #expect(throws: NotesError.self) {
            _ = try await mock.requestAccess()
        }
    }

    @Test("Mock tracks syncCheckboxes call")
    func mockSyncCheckboxes() async throws {
        let mock = MockReminderService()
        let checkboxes = [Checkbox(text: "Test", isChecked: false)]
        try await mock.syncCheckboxes(noteID: "note-1", noteTitle: "My Note", checkboxes: checkboxes)
        #expect(mock.syncCheckboxesCalled == true)
        #expect(mock.lastSyncedNoteID == "note-1")
        #expect(mock.lastSyncedNoteTitle == "My Note")
        #expect(mock.lastSyncedCheckboxes == checkboxes)
    }

    @Test("Mock tracks completeReminder call")
    func mockCompleteReminder() async throws {
        let mock = MockReminderService()
        try await mock.completeReminder(identifier: "reminder-1")
        #expect(mock.completeReminderCalled == true)
        #expect(mock.lastCompletedIdentifier == "reminder-1")
    }

    @Test("Mock filters reminders by noteID")
    func mockFetchReminders() async throws {
        let mock = MockReminderService()
        mock.reminders = [
            ReminderInfo(identifier: "r1", title: "Task 1", isCompleted: false, noteID: "note-1"),
            ReminderInfo(identifier: "r2", title: "Task 2", isCompleted: true, noteID: "note-2"),
        ]
        let result = try await mock.fetchReminders(forNoteID: "note-1")
        #expect(result.count == 1)
        #expect(result[0].identifier == "r1")
        #expect(mock.fetchRemindersCalled == true)
        #expect(mock.lastFetchedNoteID == "note-1")
    }
}

@Suite("ReminderService Reconciliation Tests")
struct ReminderServiceReconciliationTests {

    @Test("Reminder metadata parses exact note ID and checkbox key")
    func reminderMetadataParsesExactFields() {
        let metadata = ReminderService.reminderMetadata(
            for: "notes-cli:noteID=note-1;checkboxKeyB64=UmVwZWF0IHRhc2sjMA=="
        )

        #expect(metadata?.noteID == "note-1")
        #expect(metadata?.checkboxKey == "Repeat task#0")
    }

    @Test("Reminder metadata decodes checkbox keys containing semicolons")
    func reminderMetadataDecodesSemicolonKey() {
        let encodedKey = Data("Task; with;semicolons#0".utf8).base64EncodedString()
        let metadata = ReminderService.reminderMetadata(
            for: "notes-cli:noteID=note-1;checkboxKeyB64=\(encodedKey)"
        )

        #expect(metadata?.noteID == "note-1")
        #expect(metadata?.checkboxKey == "Task; with;semicolons#0")
    }

    @Test("Legacy reminder note ID parser extracts exact ID")
    func legacyReminderNoteIDParsesExactID() {
        let noteID = ReminderService.legacyReminderNoteID(for: "noteID:note-10 extra context")
        #expect(noteID == "note-10")
    }

    @Test("Fallback title match removes prior key mapping")
    func fallbackTitleMatchRemovesPriorKeyMapping() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Note: Repeat task"
        reminder.notes = "notes-cli:noteID=note-1;checkboxKey=Repeat task#0"

        var existingByKey = ["Repeat task#0": reminder]
        var existingByTitle = ["Note: Repeat task": [reminder]]

        let consumed = ReminderService.consumeExistingReminder(
            forKey: "Repeat task#1",
            reminderTitle: "Note: Repeat task",
            existingByKey: &existingByKey,
            existingByTitle: &existingByTitle
        )

        #expect(consumed?.calendarItemIdentifier == reminder.calendarItemIdentifier)
        #expect(existingByKey.isEmpty)
        #expect(existingByTitle["Note: Repeat task"]?.isEmpty != false)
    }

    @Test("Key match removes reminder from old title bucket")
    func keyMatchRemovesReminderFromOldTitleBucket() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Old Note: Repeat task"
        reminder.notes = "notes-cli:noteID=note-1;checkboxKey=Repeat task#0"

        var existingByKey = ["Repeat task#0": reminder]
        var existingByTitle = [
            "Old Note: Repeat task": [reminder],
            "New Note: Repeat task": [],
        ]

        let consumed = ReminderService.consumeExistingReminder(
            forKey: "Repeat task#0",
            reminderTitle: "New Note: Repeat task",
            existingByKey: &existingByKey,
            existingByTitle: &existingByTitle
        )

        #expect(consumed?.calendarItemIdentifier == reminder.calendarItemIdentifier)
        #expect(existingByKey.isEmpty)
        #expect(existingByTitle["Old Note: Repeat task"]?.isEmpty != false)
    }

    @Test("Deduplicated reminders removes duplicate identifiers")
    func deduplicatedRemindersRemovesDuplicates() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Note: Repeat task"

        let deduplicated = ReminderService.deduplicatedReminders([reminder, reminder])

        #expect(deduplicated.count == 1)
    }
}
