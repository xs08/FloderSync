import XCTest
@testable import obsSync

final class JSONProfileStoreTests: XCTestCase {
    func testProfilesRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsSync-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONProfileStore(fileURL: directory.appendingPathComponent("configuration.json"))
        let profiles = [SyncProfile(name: "Notes", localPath: "/tmp/Notes")]
        let rules = [AutomationRule(name: "Rule 1")]
        let configuration = AppConfiguration(profiles: profiles, automationRules: rules)

        try await store.saveConfiguration(configuration)
        let loaded = try await store.loadConfiguration()

        XCTAssertEqual(loaded, configuration)
    }

    func testMissingStoreLoadsAsEmpty() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsSync-missing-\(UUID().uuidString)/configuration.json")
        let store = JSONProfileStore(fileURL: url)

        let loaded = try await store.loadConfiguration()

        XCTAssertEqual(loaded, .empty)
    }

    func testSchemaV1MigratesToCustomRebaseConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsSync-v1-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("configuration.json")
        let profileID = UUID()
        let json = """
        {
          "schemaVersion": 1,
          "profiles": [{
            "id": "\(profileID.uuidString)",
            "name": "Notes",
            "localPath": "/tmp/Notes",
            "remoteName": "origin",
            "commitMessageTemplate": "Sync {timestamp}",
            "policies": [{"fileChanges": {}}, {"interval": {"seconds": 600}}],
            "isEnabled": true
          }]
        }
        """
        try Data(json.utf8).write(to: url)

        let loaded = try await JSONProfileStore(fileURL: url).loadConfiguration()

        XCTAssertTrue(loaded.automationRules.isEmpty)
        XCTAssertEqual(loaded.profiles.first?.automationRuleID, nil)
        XCTAssertEqual(loaded.profiles.first?.fileChangeDebounceSeconds, 5)
        XCTAssertEqual(loaded.profiles.first?.intervalSeconds, 600)
        XCTAssertEqual(loaded.profiles.first?.integrationStrategy, .rebase)
    }
}
