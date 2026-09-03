import Foundation

struct CatchUpCalculator {
    static func shouldRunCatchUp(
        profile: SyncProfile,
        lastRunAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard profile.isEnabled, let lastRunAt, lastRunAt < now else { return false }

        for policy in profile.policies {
            switch policy {
            case let .interval(seconds):
                if seconds >= 60, now.timeIntervalSince(lastRunAt) >= seconds {
                    return true
                }
            case let .daily(times):
                for time in times {
                    var components = DateComponents()
                    components.hour = time.hour
                    components.minute = time.minute
                    components.second = 0
                    if let previous = calendar.nextDate(
                        after: now,
                        matching: components,
                        matchingPolicy: .nextTime,
                        repeatedTimePolicy: .first,
                        direction: .backward
                    ), previous > lastRunAt {
                        return true
                    }
                }
            case .newCommits:
                continue
            }
        }
        return false
    }
}
