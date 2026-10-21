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

    /// Keeps the branded splash on screen for a brief minimum so it doesn't flash
    /// by. The splash still ends as soon as BOTH this elapses and the session
    /// check finishes — it never blocks a ready app beyond this short window.
    @State private var minSplashElapsed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isLoading || !minSplashElapsed {
                    SplashView()
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
            .task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)   // ~1.4s minimum
                minSplashElapsed = true
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
