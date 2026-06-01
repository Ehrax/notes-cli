import Foundation
@testable import NotesCore

public final class MockAttachmentResolver: AttachmentResolver, @unchecked Sendable {
    public var inlineTexts: [String: String] = [:]
    public var tableData: [String: Data] = [:]
    public var urlCards: [String: (title: String, url: String)] = [:]
    public var internalLinks: [String: String] = [:]

    public init() {}

    public func resolveInlineText(uuid: String) -> String? { inlineTexts[uuid] }
    public func resolveTableData(uuid: String) -> Data? { tableData[uuid] }
    public func resolveURLCard(uuid: String) -> (title: String, url: String)? { urlCards[uuid] }
    public func resolveInternalLink(uuid: String) -> String? { internalLinks[uuid] }
}
