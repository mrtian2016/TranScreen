import Foundation

enum AppDisplayLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case hindi = "hi"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .hindi: return "हिन्दी"
        }
    }

    static func normalized(_ code: String?) -> String {
        guard let code, Self(rawValue: code) != nil else { return L10n.defaultLanguage }
        return code
    }
}

enum L10n {
    static let defaultLanguage = AppDisplayLanguage.simplifiedChinese.rawValue
    static let displayLanguageDefaultsKey = "displayLanguage"

    static var currentLanguage: String {
        AppDisplayLanguage.normalized(UserDefaults.standard.string(forKey: displayLanguageDefaultsKey))
    }

    static func applySavedLanguage() {
        let language = currentLanguage
        UserDefaults.standard.set(language, forKey: displayLanguageDefaultsKey)
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    static func setPreferredLanguage(_ language: String) {
        let normalized = AppDisplayLanguage.normalized(language)
        UserDefaults.standard.set(normalized, forKey: displayLanguageDefaultsKey)
        UserDefaults.standard.set([normalized], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    static func tr(_ key: String) -> String {
        tr(key, language: currentLanguage)
    }

    static func tr(_ key: String, language: String) -> String {
        localizedBundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale(identifier: currentLanguage), arguments: arguments)
    }

    private static var localizedBundle: Bundle {
        localizedBundle(for: currentLanguage)
    }

    private static func localizedBundle(for language: String) -> Bundle {
        let normalized = AppDisplayLanguage.normalized(language)
        if let path = Bundle.main.path(forResource: normalized, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.main.path(forResource: defaultLanguage, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
