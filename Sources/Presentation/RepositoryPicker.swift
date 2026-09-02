import AppKit

@MainActor
final class RepositoryPicker {
    static let shared = RepositoryPicker()

    private var panel: NSOpenPanel?
    private var continuation: CheckedContinuation<URL?, Never>?

    var isPresented: Bool { panel != nil }

    private init() { }

    func chooseRepository() async -> URL? {
        cancel()

        return await withCheckedContinuation { continuation in
            let panel = makePanel()
            self.panel = panel
            self.continuation = continuation
            panel.begin { [weak self, weak panel] response in
                let url = response == .OK ? panel?.url : nil
                self?.finish(with: url)
            }
        }
    }

    func cancel() {
        guard let panel else { return }
        panel.cancel(nil)
        finish(with: nil)
    }

    private func makePanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = L10n.string("repository.picker.title", table: .settings)
        panel.prompt = L10n.string("repository.picker.action", table: .settings)
        panel.message = L10n.string("repository.picker.message", table: .settings)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        return panel
    }

    private func finish(with url: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        panel = nil
        continuation.resume(returning: url)
    }
}
