import AppKit

@MainActor
final class SystemWakeMonitor {
    private var token: NSObjectProtocol?

    func start(handler: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in handler() }
        }
    }

    func stop() {
        guard let token else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(token)
        self.token = nil
    }
}
