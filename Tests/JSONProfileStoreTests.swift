import XCTest
@testable import obsSync

final class JSONProfileStoreTests: XCTestCase {
    func testProfilesRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsSync-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONProfileStore(fileURL: directory.appendingPathComponent("configuration.json"))
        let profiles = [SyncProfile(name: "Notes", localPath: "/tmp/Notes")]

        try await store.saveProfiles(profiles)
        let loaded = try await store.loadProfiles()

        XCTAssertEqual(loaded, profiles)
    }

    func testMissingStoreLoadsAsEmpty() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsSync-missing-\(UUID().uuidString)/configuration.json")
        let store = JSONProfileStore(fileURL: url)

        let loaded = try await store.loadProfiles()

        XCTAssertTrue(loaded.isEmpty)
    }
}
