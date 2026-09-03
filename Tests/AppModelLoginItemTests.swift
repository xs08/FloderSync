import XCTest
@testable import floderSync

@MainActor
final class AppModelLoginItemTests: XCTestCase {
    func testRefreshLaunchAtLoginStatusReadsLatestSystemState() async {
        let loginItems = LoginItemServiceStub(status: .requiresApproval)
        let model = AppModel(loginItemService: loginItems)

        await model.refreshLaunchAtLoginStatus()
        XCTAssertEqual(model.launchAtLoginStatus, .requiresApproval)

        loginItems.currentStatus = .enabled
        await model.refreshLaunchAtLoginStatus()

        XCTAssertEqual(model.launchAtLoginStatus, .enabled)
        XCTAssertEqual(loginItems.statusCallCount, 2)
    }

    func testChangingLaunchAtLoginRequeriesAuthoritativeSystemState() async {
        let changed = expectation(description: "login item changed")
        let loginItems = LoginItemServiceStub(status: .disabled) {
            changed.fulfill()
        }
        let model = AppModel(loginItemService: loginItems)

        model.setLaunchAtLogin(true)
        await fulfillment(of: [changed], timeout: 1)
        while loginItems.statusCallCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(loginItems.enabledValues, [true])
        XCTAssertEqual(loginItems.statusCallCount, 1)
        XCTAssertEqual(model.launchAtLoginStatus, .enabled)
    }
}

@MainActor
private final class LoginItemServiceStub: LoginItemManaging {
    var currentStatus: LoginItemStatus
    private let didChange: (() -> Void)?
    private(set) var statusCallCount = 0
    private(set) var enabledValues: [Bool] = []

    init(status: LoginItemStatus, didChange: (() -> Void)? = nil) {
        self.currentStatus = status
        self.didChange = didChange
    }

    func status() async -> LoginItemStatus {
        statusCallCount += 1
        return currentStatus
    }

    func setEnabled(_ enabled: Bool) async throws {
        enabledValues.append(enabled)
        currentStatus = enabled ? .enabled : .disabled
        didChange?()
    }

    func openSystemSettings() async {}
}
