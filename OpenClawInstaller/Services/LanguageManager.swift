import SwiftUI
import Combine

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @AppStorage("appLanguage") var selectedLanguage: String = "system" {
        didSet { objectWillChange.send() }
    }

    struct Language: Identifiable, Hashable {
        let id: String      // locale identifier
        let name: String    // native name for display
    }

    let supportedLanguages: [Language] = [
        Language(id: "system", name: "System"),
        Language(id: "en",      name: "English"),
        Language(id: "ar",      name: "العربية"),
        Language(id: "zh-Hans", name: "简体中文"),
        Language(id: "zh-Hant", name: "繁體中文"),
        Language(id: "da",      name: "Dansk"),
        Language(id: "nl",      name: "Nederlands"),
        Language(id: "fil",     name: "Filipino"),
        Language(id: "fi",      name: "Suomi"),
        Language(id: "fr",      name: "Français"),
        Language(id: "de",      name: "Deutsch"),
        Language(id: "el",      name: "Ελληνικά"),
        Language(id: "hu",      name: "Magyar"),
        Language(id: "id",      name: "Indonesia"),
        Language(id: "it",      name: "Italiano"),
        Language(id: "ja",      name: "日本語"),
        Language(id: "ko",      name: "한국어"),
        Language(id: "ms",      name: "Melayu"),
        Language(id: "fa",      name: "فارسی"),
        Language(id: "pl",      name: "Polski"),
        Language(id: "pt-BR",   name: "Português"),
        Language(id: "ru",      name: "Русский"),
        Language(id: "es",      name: "Español"),
        Language(id: "sv",      name: "Svenska"),
        Language(id: "th",      name: "ไทย"),
        Language(id: "tr",      name: "Türkçe"),
        Language(id: "vi",      name: "Tiếng Việt"),
    ]

    /// Returns a Locale override when the user has chosen a specific language,
    /// or nil to follow the system setting.
    var currentLocale: Locale? {
        guard selectedLanguage != "system" else { return nil }
        return Locale(identifier: selectedLanguage)
    }

    /// Display name shown in the language picker button.
    var displayName: String {
        if selectedLanguage == "system" { return "System" }
        return supportedLanguages.first { $0.id == selectedLanguage }?.name ?? selectedLanguage
    }

    /// The globe icon for the current language direction.
    var globeIcon: String { "globe" }
}
