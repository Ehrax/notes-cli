import Foundation

public struct ExportResult: Codable, Sendable {
    public var exported: Int
    public var skipped: Int
    public var partial: Int
    public var folders: Int
    public var format: String
    public var outputPath: String

    public init(
        exported: Int, skipped: Int, partial: Int = 0,
        folders: Int, format: String, outputPath: String
    ) {
        self.exported = exported
        self.skipped = skipped
        self.partial = partial
        self.folders = folders
        self.format = format
        self.outputPath = outputPath
    }
}
