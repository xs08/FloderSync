import XCTest
@testable import floderSync

final class JSONProfileStoreTests: XCTestCase {
    func testProfilesRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floderSync-store-test-\(UUID().uuidString)", isDirectory: true)
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
            .appendingPathComponent("floderSync-missing-\(UUID().uuidString)/configuration.json")
        let store = JSONProfileStore(fileURL: url)

        let loaded = try await store.loadConfiguration()

        XCTAssertEqual(loaded, .empty)
    }

    func testSchemaV1MigratesToCustomRebaseConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floderSync-v1-store-test-\(UUID().uuidString)", isDirectory: true)
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
        XCTAssertEqual(loaded.profiles.first?.watchesNewCommits, true)
        XCTAssertEqual(loaded.profiles.first?.intervalSeconds, 600)
        XCTAssertEqual(loaded.profiles.first?.integrationStrategy, .rebase)
        XCTAssertEqual(loaded.profiles.first?.automaticCommit.isEnabled, true)
        XCTAssertEqual(loaded.profiles.first?.automaticCommit.messageTemplate, "Sync {timestamp}")
    }

    func testSchemaV2MigratesAutomaticCommitForCustomAndRuleConfigurations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floderSync-v2-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("configuration.json")
        let customProfileID = UUID()
        let ruleProfileID = UUID()
        let ruleID = UUID()
        let json = """
        {
          "schemaVersion": 2,
          "profiles": [
            {
              "id": "\(customProfileID.uuidString)",
              "name": "Custom",
              "localPath": "/tmp/Custom",
              "remoteName": "origin",
              "commitMessageTemplate": "Custom ${user}",
              "customAutomationConfiguration": {
                "policies": [{"interval": {"seconds": 300}}],
                "integrationStrategy": "rebase"
              },
              "isEnabled": true
            },
            {
              "id": "\(ruleProfileID.uuidString)",
              "name": "Rule Repository",
              "localPath": "/tmp/Rule",
              "remoteName": "origin",
              "commitMessageTemplate": "Rule ${time}",
              "customAutomationConfiguration": {
                "policies": [{"fileChanges": {"debounceSeconds": 5}}],
                "integrationStrategy": "rebase"
              },
              "automationRuleID": "\(ruleID.uuidString)",
              "isEnabled": true
            }
          ],
          "automationRules": [{
            "id": "\(ruleID.uuidString)",
            "name": "Shared",
            "configuration": {
              "policies": [{"daily": {"times": [{"hour": 9, "minute": 30}]}}],
              "integrationStrategy": "merge"
            }
          }]
        }
        """
        try Data(json.utf8).write(to: url)

        let loaded = try await JSONProfileStore(fileURL: url).loadConfiguration()

        let custom = try XCTUnwrap(loaded.profiles.first(where: { $0.id == customProfileID }))
        XCTAssertTrue(custom.automaticCommit.isEnabled)
        XCTAssertEqual(custom.automaticCommit.messageTemplate, "Custom ${user}")
        let rule = try XCTUnwrap(loaded.automationRules.first)
        XCTAssertTrue(rule.configuration.automaticCommit.isEnabled)
        XCTAssertEqual(rule.configuration.automaticCommit.messageTemplate, "Rule ${time}")
    }

    func testSchemaV3FileChangesMigrateToNewCommitDetection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floderSync-v3-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("configuration.json")
        let profileID = UUID()
        let json = """
        {
          "schemaVersion": 3,
          "profiles": [{
            "id": "\(profileID.uuidString)",
            "name": "Notes",
            "localPath": "/tmp/Notes",
            "remoteName": "origin",
            "customAutomationConfiguration": {
              "policies": [{"fileChanges": {"debounceSeconds": 10}}],
              "integrationStrategy": "rebase",
              "automaticCommit": {
                "isEnabled": true,
                "messageTemplate": "Sync"
              }
            },
            "isEnabled": true
          }],
          "automationRules": []
        }
        """
        try Data(json.utf8).write(to: url)

        let loaded = try await JSONProfileStore(fileURL: url).loadConfiguration()

        XCTAssertEqual(loaded.profiles.first?.watchesNewCommits, true)
    }

    func testCurrentSchemaWritesVersionFourAndNewCommitPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("floderSync-v4-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("configuration.json")
        let store = JSONProfileStore(fileURL: url)

        try await store.saveConfiguration(AppConfiguration(
            profiles: [SyncProfile(name: "Notes", localPath: "/tmp/Notes")],
            automationRules: []
        ))
        let json = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(json.contains("\"schemaVersion\" : 4"))
        XCTAssertTrue(json.contains("\"newCommits\""))
        XCTAssertFalse(json.contains("\"fileChanges\""))
    }
}
