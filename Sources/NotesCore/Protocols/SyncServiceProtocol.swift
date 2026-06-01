import Foundation

public protocol SyncServiceProtocol: Sendable {
    func fullSync() async throws -> SyncResult
    func incrementalSync() async throws -> SyncResult
}
