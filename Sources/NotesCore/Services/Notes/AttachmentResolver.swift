import Foundation

/// Protocol for resolving Apple Notes inline attachments during protobuf conversion.
/// Ref: obsidian-importer convert-note.ts formatAttachment() lines 302-382
public protocol AttachmentResolver: Sendable {
    /// Resolve inline text for hashtag/mention (queries ZALTTEXT)
    func resolveInlineText(uuid: String) -> String?

    /// Resolve gzipped CRDT protobuf for table (queries ZMERGEABLEDATA1)
    func resolveTableData(uuid: String) -> Data?

    /// Resolve URL card title + URL (queries ZTITLE, ZURLSTRING)
    func resolveURLCard(uuid: String) -> (title: String, url: String)?

    /// Resolve internal note link identifier (queries ZTOKENCONTENTIDENTIFIER)
    func resolveInternalLink(uuid: String) -> String?
}
