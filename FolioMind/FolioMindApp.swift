//
//  FolioMindApp.swift
//  FolioMind
//
//  Created by Jay Zeng on 11/23/25.
//

import SwiftUI
import SwiftData

@main
struct FolioMindApp: App {
    @StateObject private var services = AppServices()
    @StateObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services)
                .environment(\.locale, languageManager.locale)
        }
        .modelContainer(services.modelContainer)
    }
}
