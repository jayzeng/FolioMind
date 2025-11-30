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
        let languageCode: String?

        switch currentLanguage {
        case .system:
            languageCode = nil
        case .english:
            languageCode = "en"
        case .simplifiedChinese:
            languageCode = "zh-Hans"
        case .traditionalChinese:
            languageCode = "zh-Hant"
        }

        if let code = languageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        UserDefaults.standard.synchronize()
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }

    var needsRestart: Bool {
        // Check if the current language preference is different from what's applied
        let appliedLanguages = UserDefaults.standard.stringArray(forKey: "AppleLanguages")

        switch currentLanguage {
        case .system:
            return appliedLanguages != nil
        case .english:
            return appliedLanguages?.first != "en"
        case .simplifiedChinese:
            return appliedLanguages?.first != "zh-Hans"
        case .traditionalChinese:
            return appliedLanguages?.first != "zh-Hant"
        }
    }
}
