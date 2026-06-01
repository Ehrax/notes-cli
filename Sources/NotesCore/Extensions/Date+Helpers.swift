import Foundation

extension Date {
    /// Formats the date as an ISO 8601 string (e.g. "2026-03-08T12:34:56Z").
    public var iso8601String: String {
        Date.iso8601Formatter.string(from: self)
    }

    /// Parses an ISO 8601 string into a Date, or returns nil if invalid.
    public static func fromISO8601(_ string: String) -> Date? {
        iso8601Formatter.date(from: string)
    }

    /// A human-readable relative description (e.g. "2 hours ago").
    public var relativeString: String {
        Date.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }

    // MARK: - Shared formatters

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
