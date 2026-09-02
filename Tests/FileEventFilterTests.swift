import XCTest
@testable import obsSync

final class FileEventFilterTests: XCTestCase {
    func testGitInternalChangesAreIgnored() {
        XCTAssertFalse(FileEventFilter.hasRelevantChange(
            paths: ["/tmp/Notes/.git/index", "/tmp/Notes/.git/refs/heads/main"],
            repositoryRoot: "/tmp/Notes"
        ))
    }

    func testWorkingTreeChangesAreRelevant() {
        XCTAssertTrue(FileEventFilter.hasRelevantChange(
            paths: ["/tmp/Notes/Projects/Plan.md"],
            repositoryRoot: "/tmp/Notes"
        ))
    }
}
