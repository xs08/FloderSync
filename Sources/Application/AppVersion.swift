import Foundation

struct AppVersion: Equatable, Sendable {
    static let fallbackSemanticVersion = "0.0.0"

    let semanticVersion: String

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary)
    }

    init(infoDictionary: [String: Any]?) {
        let bundledVersion = (infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        semanticVersion = bundledVersion.flatMap(Self.nonEmpty) ?? Self.fallbackSemanticVersion
    }

    static var current: Self {
        Self()
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
