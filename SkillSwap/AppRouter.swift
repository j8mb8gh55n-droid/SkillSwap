//
//  AppRouter.swift
//  SkillSwap
//
//  Single source of truth for cross-tab navigation. ContentView owns the
//  selected tab; main sections switch the tab (and pass a deep-link payload)
//  instead of pushing another copy of a tab's root view. Detail screens
//  (student profiles, exchange details) still push onto their tab's own
//  NavigationStack so native back navigation is preserved.
//

import SwiftUI
import Combine

@MainActor
final class AppRouter: ObservableObject {

    enum Tab: Hashable { case home, explore, exchanges, profile }

    /// The currently selected bottom tab (ContentView binds the TabView to this).
    @Published var tab: Tab = .home

    /// Pending category for Explore. Explore applies it on appear, then clears it.
    @Published var exploreCategory: String?

    /// An exchange to open in the Exchanges tab's details screen.
    @Published var pendingExchange: SkillExchange?

    // MARK: - Intents

    func openExplore(category: String? = nil) {
        exploreCategory = category
        tab = .explore
    }

    func openProfile() {
        tab = .profile
    }

    func openExchangeDetails(_ exchange: SkillExchange) {
        pendingExchange = exchange
        tab = .exchanges
    }
}
