import Foundation

enum SyncCoordinatorEvent: Sendable {
    case started(profileID: UUID)
    case finished(SyncRunRecord)
    case becameIdle(profileID: UUID)
}

actor SyncCoordinator {
    nonisolated let events: AsyncStream<SyncCoordinatorEvent>

    private struct Request: Sendable {
        let profile: SyncProfile
        let trigger: SyncTrigger
        let automationRuleName: String?
    }

    private let engine: SyncEngine
    private let eventContinuation: AsyncStream<SyncCoordinatorEvent>.Continuation
    private let maximumConcurrentRepositories: Int
    private var activeProfileIDs: Set<UUID> = []
    private var pendingByProfileID: [UUID: Request] = [:]
    private var waiting: [Request] = []
    private var activeCount = 0
    private var idleWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    init(engine: SyncEngine, maximumConcurrentRepositories: Int = 2) {
        let pair = AsyncStream.makeStream(of: SyncCoordinatorEvent.self, bufferingPolicy: .bufferingNewest(256))
        self.events = pair.stream
        self.eventContinuation = pair.continuation
        self.engine = engine
        self.maximumConcurrentRepositories = max(1, maximumConcurrentRepositories)
    }

    deinit {
        eventContinuation.finish()
    }

    func enqueue(
        profile: SyncProfile,
        trigger: SyncTrigger,
        automationRuleName: String? = nil
    ) {
        let request = Request(
            profile: profile,
            trigger: trigger,
            automationRuleName: automationRuleName
        )
        if activeProfileIDs.contains(profile.id) {
            pendingByProfileID[profile.id] = merge(
                existing: pendingByProfileID[profile.id],
                incoming: request
            )
            return
        }

        activeProfileIDs.insert(profile.id)
        waiting.append(request)
        startWaitingRequestsIfPossible()
    }

    func waitUntilIdle(profileID: UUID) async {
        guard activeProfileIDs.contains(profileID) else { return }
        await withCheckedContinuation { continuation in
            idleWaiters[profileID, default: []].append(continuation)
        }
    }

    func isActive(profileID: UUID) -> Bool {
        activeProfileIDs.contains(profileID)
    }

    private func startWaitingRequestsIfPossible() {
        while activeCount < maximumConcurrentRepositories, !waiting.isEmpty {
            let request = waiting.removeFirst()
            activeCount += 1
            Task { await drain(request) }
        }
    }

    private func drain(_ initialRequest: Request) async {
        var request = initialRequest

        while true {
            eventContinuation.yield(.started(profileID: request.profile.id))
            let record = await engine.synchronize(
                profile: request.profile,
                trigger: request.trigger,
                automationRuleName: request.automationRuleName
            )
            eventContinuation.yield(.finished(record))

            if let pending = pendingByProfileID.removeValue(forKey: request.profile.id) {
                request = pending
            } else {
                break
            }
        }

        let profileID = request.profile.id
        activeProfileIDs.remove(profileID)
        activeCount -= 1
        eventContinuation.yield(.becameIdle(profileID: profileID))
        idleWaiters.removeValue(forKey: profileID)?.forEach { $0.resume() }
        startWaitingRequestsIfPossible()
    }

    private func merge(existing: Request?, incoming: Request) -> Request {
        guard let existing else { return incoming }
        let trigger: SyncTrigger
        if existing.trigger == .manual || incoming.trigger == .manual {
            trigger = .manual
        } else if existing.trigger == .wakeCatchUp || incoming.trigger == .wakeCatchUp {
            trigger = .wakeCatchUp
        } else {
            trigger = incoming.trigger
        }
        return Request(
            profile: incoming.profile,
            trigger: trigger,
            automationRuleName: incoming.automationRuleName
        )
    }
}
