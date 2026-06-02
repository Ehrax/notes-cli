public enum ExportFormat: String, Sendable, CaseIterable {
    case json
    case md

    public var fileExtension: String {
        rawValue
    }
}
