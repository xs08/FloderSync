import XCTest
@testable import floderSync

final class CommitChangeSchedulerTests: XCTestCase {
    func testOnlyHeadAndLocalBranchMetadataCanSignalACommit() {
        let gitDirectory = "/tmp/Notes/.git"

        XCTAssertTrue(CommitEventFilter.hasPotentialRevisionChange(
            paths: ["/tmp/Notes/.git/refs/heads/main"],
            gitDirectory: gitDirectory
        ))
        XCTAssertTrue(CommitEventFilter.hasPotentialRevisionChange(
            paths: ["/tmp/Notes/.git/logs/HEAD"],
            gitDirectory: gitDirectory
        ))
        XCTAssertFalse(CommitEventFilter.hasPotentialRevisionChange(
            paths: ["/tmp/Notes/Projects/Plan.md", "/tmp/Notes/.git/index"],
            gitDirectory: gitDirectory
        ))
    }

    func testSynchronizationRevisionDoesNotCauseAnotherTrigger() {
        var state = CommitRevisionState(baseline: "before")

        state.beginSynchronization()
        XCTAssertFalse(state.observe("automatic-commit"))
        state.endSynchronization(currentRevision: "after-sync")

        XCTAssertFalse(state.observe("after-sync"))
        XCTAssertTrue(state.observe("external-commit"))
    }

    func testFirstObservedRevisionOnlyEstablishesBaseline() {
        var state = CommitRevisionState()

        XCTAssertFalse(state.observe("initial"))
        XCTAssertTrue(state.observe("next"))
    }
}
