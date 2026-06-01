public enum ExportFormat: String, Sendable, CaseIterable {
    case md

    public var fileExtension: String {
        rawValue
    }
}
