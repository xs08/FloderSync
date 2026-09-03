import Foundation

struct ScheduleCalculator {
    static func nextDailyDate(
        after date: Date,
        times: [DailyTime],
        calendar: Calendar = .current
    ) -> Date? {
        times.compactMap { time in
            var components = DateComponents()
            components.hour = time.hour
            components.minute = time.minute
            components.second = 0
            return calendar.nextDate(
                after: date,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }.min()
    }
}

actor AutomationScheduler {
    typealias TriggerHandler = @Sendable (SyncProfile, SyncTrigger) async -> Void

    private var tasks: [Task<Void, Never>] = []

    deinit {
        tasks.forEach { $0.cancel() }
    }

    func configure(profiles: [SyncProfile], onTrigger: @escaping TriggerHandler) {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()

        for profile in profiles where profile.isEnabled {
            for policy in profile.policies {
                switch policy {
                case let .daily(times):
                    guard !times.isEmpty else { continue }
                    tasks.append(Task {
                        await Self.runDaily(profile: profile, times: times, onTrigger: onTrigger)
                    })
                case let .interval(seconds):
                    guard seconds >= 60 else { continue }
                    tasks.append(Task {
                        await Self.runInterval(profile: profile, seconds: seconds, onTrigger: onTrigger)
                    })
                case .newCommits:
                    break
                }
            }
        }
    }

    private static func runDaily(
        profile: SyncProfile,
        times: [DailyTime],
        onTrigger: @escaping TriggerHandler
    ) async {
        while !Task.isCancelled {
            guard let next = ScheduleCalculator.nextDailyDate(after: Date(), times: times) else { return }
            let nanoseconds = nanosecondsUntil(next)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                try Task.checkCancellation()
                await onTrigger(profile, .scheduled)
            } catch {
                return
            }
        }
    }

    private static func runInterval(
        profile: SyncProfile,
        seconds: TimeInterval,
        onTrigger: @escaping TriggerHandler
    ) async {
        let nanoseconds = UInt64(min(seconds, 31_536_000) * 1_000_000_000)
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                try Task.checkCancellation()
                await onTrigger(profile, .interval)
            } catch {
                return
            }
        }
    }

    private static func nanosecondsUntil(_ date: Date) -> UInt64 {
        let seconds = max(0, date.timeIntervalSinceNow)
        return UInt64(min(seconds, 31_536_000) * 1_000_000_000)
    }
}
