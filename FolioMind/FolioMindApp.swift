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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(services)
        }
        .modelContainer(services.modelContainer)
    }
}
