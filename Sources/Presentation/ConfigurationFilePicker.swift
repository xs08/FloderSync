import AppKit
import UniformTypeIdentifiers

@MainActor
final class ConfigurationFilePicker {
    static let shared = ConfigurationFilePicker()

    private var panel: NSSavePanel?
    private var continuation: CheckedContinuation<URL?, Never>?

    private init() { }

    func chooseImportFile() async -> URL? {
        cancel()
        RepositoryPicker.shared.cancel()
        let panel = NSOpenPanel()
        panel.title = L10n.string("configuration.import.picker.title", table: .settings)
        panel.prompt = L10n.string("configuration.import.action", table: .settings)
        panel.message = L10n.string("configuration.import.picker.message", table: .settings)
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        return await present(panel)
    }

    func chooseExportDestination() async -> URL? {
        cancel()
        RepositoryPicker.shared.cancel()
        let panel = NSSavePanel()
        panel.title = L10n.string("configuration.export.picker.title", table: .settings)
        panel.prompt = L10n.string("configuration.export.action", table: .settings)
        panel.message = L10n.string("configuration.export.picker.message", table: .settings)
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "FloderSync-configuration.json"
        return await present(panel)
    }

    func cancel() {
        guard let panel else { return }
        panel.cancel(nil)
        finish(with: nil)
    }

    private func present(_ panel: NSSavePanel) async -> URL? {
        await withCheckedContinuation { continuation in
            self.panel = panel
            self.continuation = continuation
            panel.begin { [weak self, weak panel] response in
                self?.finish(with: response == .OK ? panel?.url : nil)
            }
        }
    }

    private func finish(with url: URL?) {
        guard let continuation else { return }
        self.continuation = nil
        panel = nil
        continuation.resume(returning: url)
    }
}
