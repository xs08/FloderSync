import Foundation
import XCTest
@testable import floderSync

final class LocalizationCatalogTests: XCTestCase {
    @MainActor
    func testThemeSelectionPersistsAndRestores() {
        let defaults = UserDefaults.standard
        let originalValue = defaults.string(forKey: AppTheme.defaultsKey)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: AppTheme.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppTheme.defaultsKey)
            }
        }

        defaults.set(AppTheme.dark.rawValue, forKey: AppTheme.defaultsKey)
        let model = AppModel()

        XCTAssertEqual(AppTheme.selected, .dark)
        XCTAssertEqual(model.appTheme, .dark)

        model.setAppTheme(.light)

        XCTAssertEqual(model.appTheme, .light)
        XCTAssertEqual(AppTheme.selected, .light)

        defaults.set("unsupported-theme", forKey: AppTheme.defaultsKey)
        XCTAssertEqual(AppTheme.selected, .system)

        defaults.removeObject(forKey: AppTheme.defaultsKey)
        XCTAssertEqual(AppTheme.selected, .system)
    }

    func testExplicitLanguageSelectionChangesLocalizedStringsImmediately() {
        let defaults = UserDefaults.standard
        let originalValue = defaults.string(forKey: AppLanguage.defaultsKey)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: AppLanguage.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.defaultsKey)
            }
        }

        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(L10n.string("settings.general"), "General")

        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.defaultsKey)
        XCTAssertEqual(L10n.string("settings.general"), "通用")
    }

    func testLanguagePickerUsesEachLanguagesOwnName() {
        XCTAssertEqual(
            AppLanguage.english.pickerTitle(interfaceLanguage: .simplifiedChinese),
            "English"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.pickerTitle(interfaceLanguage: .english),
            "简体中文"
        )
        XCTAssertEqual(
            AppLanguage.system.pickerTitle(interfaceLanguage: .english),
            "Follows System Settings (English and Simplified Chinese)"
        )
        XCTAssertEqual(
            AppLanguage.system.pickerTitle(interfaceLanguage: .simplifiedChinese),
            "跟随系统设置（英文和简体中文）"
        )
    }

    func testExplicitLocalizationLanguageDoesNotDependOnSavedSelection() {
        let defaults = UserDefaults.standard
        let originalValue = defaults.string(forKey: AppLanguage.defaultsKey)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: AppLanguage.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.defaultsKey)
            }
        }

        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.defaultsKey)

        XCTAssertEqual(
            L10n.string("settings.repositories", language: .simplifiedChinese),
            "仓库"
        )
        XCTAssertEqual(
            L10n.string("settings.automation", language: .english),
            "Automation"
        )
    }

    func testEveryCatalogEntryHasEnglishAndSimplifiedChineseTranslations() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resourcesURL = projectRoot.appendingPathComponent("Resources", isDirectory: true)
        let catalogURLs = try FileManager.default.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "xcstrings" }

        XCTAssertFalse(catalogURLs.isEmpty)

        for catalogURL in catalogURLs {
            let data = try Data(contentsOf: catalogURL)
            let root = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any],
                catalogURL.lastPathComponent
            )
            let strings = try XCTUnwrap(
                root["strings"] as? [String: Any],
                catalogURL.lastPathComponent
            )

            for (key, rawEntry) in strings {
                let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
                for language in ["en", "zh-Hans"] {
                    let localization = try XCTUnwrap(
                        localizations[language] as? [String: Any],
                        "\(catalogURL.lastPathComponent): \(key) is missing \(language)"
                    )
                    let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], key)
                    let value = try XCTUnwrap(unit["value"] as? String, key)
                    XCTAssertFalse(
                        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "\(catalogURL.lastPathComponent): \(key) has an empty \(language) value"
                    )
                }
            }
        }
    }
}
