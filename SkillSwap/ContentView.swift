//
//  ContentView.swift
//  SkillSwap
//
//  Created by mac on 06/05/1448 AH.
//

import SwiftUI
import Supabase

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    @StateObject private var savedStudents = SavedStudentsStore()
    @StateObject private var directory = StudentDirectory()

    @State private var chatDrafts = ChatDraftStore()
    #if DEBUG
    @State private var showCommunity = ProcessInfo.processInfo.arguments.contains("--community")
    #endif

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

            ChatsView()
                .tag(AppRouter.Tab.chats)
                .tabItem {
                    Label("Chats", systemImage: router.tab == .chats
                          ? "bubble.left.and.bubble.right.fill"
                          : "bubble.left.and.bubble.right")
                        .symbolVariant(.none)
                }

            ProfileView()
                .tag(AppRouter.Tab.profile)
                .tabItem { Label("Profile", systemImage: "person") }

        }
        #if DEBUG
        .fullScreenCover(isPresented: $showCommunity) {
            NavigationStack { CommunityView() }
        }
        #endif
        .environment(\.chatDraftStore, chatDrafts)
        .tint(Theme.primaryAction)
        .environmentObject(router)
        .environmentObject(savedStudents)
        .environmentObject(directory)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await directory.refresh() } }
        }
        .onChange(of: router.tab) { _, tab in
            if tab == .home || tab == .explore { Task { await directory.refresh() } }
        }
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
