import Foundation
import UserNotifications

protocol FailureNotificationSending: Sendable {
    func requestAuthorization() async throws -> Bool
    func sendFailure(for run: SyncRunRecord, profileName: String) async throws
}

struct UserNotificationService: FailureNotificationSending {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func sendFailure(for run: SyncRunRecord, profileName: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("notification.failure.title", table: .notifications)
        content.body = String(
            format: L10n.string("notification.failure.body", table: .notifications),
            profileName,
            run.failureMessage ?? L10n.string("notification.failure.unknown", table: .notifications)
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "sync-failure-\(run.id.uuidString)",
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
