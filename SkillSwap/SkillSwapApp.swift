//
//  SkillSwapApp.swift
//  SkillSwap
//
//  Created by mac on 06/05/1448 AH.
//

import SwiftUI

@main
struct SkillSwapApp: App {

    @StateObject private var authManager = AuthManager()
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isLoading {
                    Color(hex: 0xF6F0E5).ignoresSafeArea()
                } else if authManager.isAuthenticated {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(authManager)
            .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme ?? nil)
            .task {
                await authManager.checkSession()
            }
        }
    }
}

/// App-wide appearance preference (persisted in @AppStorage("appAppearance")).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
