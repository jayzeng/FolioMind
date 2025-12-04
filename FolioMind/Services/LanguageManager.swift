//
//  LanguageManager.swift
//  FolioMind
//
//  Manages app language preferences and localization.
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "language.system", defaultValue: "System Default", comment: "System language option")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .system:
            return String(localized: "language.system", defaultValue: "System Default", comment: "System language option")
        case .english:
            return String(localized: "language.english", defaultValue: "English", comment: "English language option")
        case .simplifiedChinese:
            return String(localized: "language.simplifiedChinese", defaultValue: "Simplified Chinese", comment: "Simplified Chinese language option")
        case .traditionalChinese:
            return String(localized: "language.traditionalChinese", defaultValue: "Traditional Chinese", comment: "Traditional Chinese language option")
        }
    }

    var icon: String {
        switch self {
        case .system:
            return "globe"
        case .english:
            return "🇺🇸"
        case .simplifiedChinese:
            return "🇨🇳"
        case .traditionalChinese:
            return "🇹🇼"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        }
    }
}

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            saveLanguagePreference()
            applyLanguage()
        }
    }

    private let languageKey = "AppLanguage"

    private init() {
        // Load saved language preference
        if let savedLanguage = UserDefaults.standard.string(forKey: languageKey),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .system
        }

        applyLanguage()
    }

    private func saveLanguagePreference() {
        UserDefaults.standard.set(currentLanguage.rawValue, forKey: languageKey)
    }

    private func applyLanguage() {
        let languageCode = currentLanguage.localeIdentifier

        if let code = languageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        UserDefaults.standard.synchronize()

        // Let SwiftUI know the locale changed so views can update without a manual relaunch
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }

    var locale: Locale {
        if let identifier = currentLanguage.localeIdentifier {
            return Locale(identifier: identifier)
        } else {
            return Locale.autoupdatingCurrent
        }
    }
}
