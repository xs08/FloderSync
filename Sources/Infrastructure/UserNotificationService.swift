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
        content.title = String(localized: "notification.failure.title")
        content.body = String(
            format: String(localized: "notification.failure.body"),
            profileName,
            run.failureMessage ?? String(localized: "notification.failure.unknown")
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
