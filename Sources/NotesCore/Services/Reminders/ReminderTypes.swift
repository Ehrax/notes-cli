import Foundation

/// Represents a checkbox extracted from a note's content.
public struct Checkbox: Sendable, Equatable {
    public var text: String
    public var isChecked: Bool
    public var dueDate: Date?

    public init(text: String, isChecked: Bool, dueDate: Date? = nil) {
        self.text = text
        self.isChecked = isChecked
        self.dueDate = dueDate
    }
}

/// Represents a reminder linked to a note checkbox.
public struct ReminderInfo: Sendable {
    public var identifier: String
    public var title: String
    public var isCompleted: Bool
    public var dueDate: Date?
    public var noteID: String

    public init(
        identifier: String,
        title: String,
        isCompleted: Bool,
        dueDate: Date? = nil,
        noteID: String
    ) {
        self.identifier = identifier
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.noteID = noteID
    }
}
