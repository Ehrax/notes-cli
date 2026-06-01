import Foundation

public struct ExportResult: Codable, Sendable {
    public var exported: Int
    public var skipped: Int
    public var folders: Int
    public var format: String
    public var outputPath: String

    public init(exported: Int, skipped: Int, folders: Int, format: String, outputPath: String) {
        self.exported = exported
        self.skipped = skipped
        self.folders = folders
        self.format = format
        self.outputPath = outputPath
    }
}
