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

    /// Resolve the system's preferred language to one of our supported language IDs.
    private var resolvedSystemLanguage: String {
        let supportedIDs = Set(supportedLanguages.map { $0.id }.filter { $0 != "system" })

        for preferred in Locale.preferredLanguages {
            // Direct match (e.g. "zh-Hans", "pt-BR")
            if supportedIDs.contains(preferred) {
                return preferred
            }
            let parts = preferred.split(separator: "-")
            if parts.count >= 2 {
                // Try first two segments (zh-Hans, zh-Hant, pt-BR)
                let twopart = "\(parts[0])-\(parts[1])"
                if supportedIDs.contains(twopart) {
                    return twopart
                }
            }
            // Language code only (e.g. "fr-FR" → "fr")
            let langOnly = String(parts[0])
            if supportedIDs.contains(langOnly) {
                return langOnly
            }
        }
        return "en"
    }

    /// Returns the Locale for the current language selection.
    var currentLocale: Locale {
        if selectedLanguage == "system" {
            return Locale(identifier: resolvedSystemLanguage)
        }
        return Locale(identifier: selectedLanguage)
    }

    /// Display name shown in the language picker button.
    var displayName: String {
        if selectedLanguage == "system" {
            let resolved = resolvedSystemLanguage
            let name = supportedLanguages.first { $0.id == resolved }?.name ?? "System"
            return "System (\(name))"
        }
        return supportedLanguages.first { $0.id == selectedLanguage }?.name ?? selectedLanguage
    }

    /// The globe icon for the current language direction.
    var globeIcon: String { "globe" }

    /// Returns a Bundle for the current language selection, suitable for
    /// `String(localized:bundle:)` calls outside SwiftUI views.
    var localizedBundle: Bundle {
        let langID: String
        if selectedLanguage == "system" {
            langID = resolvedSystemLanguage
        } else {
            langID = selectedLanguage
        }
        // Try to find a .lproj for the selected language
        if let path = Bundle.main.path(forResource: langID, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return Bundle.main
    }
}
