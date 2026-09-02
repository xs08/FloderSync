import XCTest
@testable import obsSync

final class JSONRunHistoryStoreTests: XCTestCase {
    func testAppendKeepsNewestRunsWithinLimit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsSync-history-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONRunHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        let profileID = UUID()

        for index in 0..<3 {
            let date = Date(timeIntervalSince1970: TimeInterval(index))
            let run = SyncRunRecord(
                id: UUID(),
                profileID: profileID,
                trigger: .manual,
                startedAt: date,
                finishedAt: date,
                result: .succeeded,
                steps: [],
                failureCategory: nil,
                failureMessage: nil,
                hadLocalChanges: false
            )
            try await store.append(run, limit: 2)
        }

        let runs = try await store.loadRuns()
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.map(\.finishedAt), [Date(timeIntervalSince1970: 2), Date(timeIntervalSince1970: 1)])
    }
}
