import Foundation

protocol RunHistoryStore: Sendable {
    func loadRuns() async throws -> [SyncRunRecord]
    func append(_ run: SyncRunRecord, limit: Int) async throws
}
