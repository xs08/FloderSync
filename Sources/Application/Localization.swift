import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    static let defaultsKey = "appLanguage"

    var id: Self { self }

    static var selected: Self {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let language = Self(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }

    fileprivate var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }
}

enum LocalizationTable: String, Sendable {
    case automation = "Automation"
    case errors = "Errors"
    case history = "History"
    case localizable = "Localizable"
    case notifications = "Notifications"
    case repositoryActions = "RepositoryActions"
    case settings = "Settings"
}

enum L10n {
    static func string(
        _ key: String,
        table: LocalizationTable = .localizable,
        language: AppLanguage = .selected
    ) -> String {
        NSLocalizedString(
            key,
            tableName: table.rawValue,
            bundle: selectedBundle(for: language),
            value: key,
            comment: ""
        )
    }

    static func format(
        _ key: String,
        table: LocalizationTable = .localizable,
        _ arguments: CVarArg...
    ) -> String {
        String(format: string(key, table: table), locale: AppLanguage.selected.locale, arguments: arguments)
    }

    private static func selectedBundle(for language: AppLanguage) -> Bundle {
        guard let identifier = language.localizationIdentifier,
              let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

extension AppLanguage {
    func pickerTitle(interfaceLanguage: AppLanguage) -> String {
        switch self {
        case .system:
            L10n.string(
                "general.language.system",
                table: .settings,
                language: interfaceLanguage
            )
        case .english:
            L10n.string("general.language.english", table: .settings, language: .english)
        case .simplifiedChinese:
            L10n.string(
                "general.language.simplifiedChinese",
                table: .settings,
                language: .simplifiedChinese
            )
        }
    }
}
