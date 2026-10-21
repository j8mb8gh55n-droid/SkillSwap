//
//  ContentView.swift
//  SkillSwap
//
//  Created by mac on 06/05/1448 AH.
//

import SwiftUI
import Supabase

struct ContentView: View {

    @StateObject private var router = AppRouter()
    @StateObject private var savedStudents = SavedStudentsStore()
    @StateObject private var directory = StudentDirectory()

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tag(AppRouter.Tab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }

            ExploreView()
                .tag(AppRouter.Tab.explore)
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }

            ExchangeView()
                .tag(AppRouter.Tab.exchanges)
                .tabItem { Label("Exchanges", systemImage: "arrow.left.arrow.right") }

            ProfileView()
                .tag(AppRouter.Tab.profile)
                .tabItem { Label("Profile", systemImage: "person") }

            // Community is retained in the codebase for a future phase but is
            // intentionally NOT shown in the bottom navigation right now.
        }
        .tint(Theme.primaryAction)
        .environmentObject(router)
        .environmentObject(savedStudents)
        .environmentObject(directory)
        .task {
            // Scope saved-students bookmarks to the authenticated account.
            if let uid = try? await SupabaseManager.client.auth.session.user.id {
                savedStudents.use(userID: uid.uuidString)
            }
        }
    }
}

#Preview {
    ContentView()
}
