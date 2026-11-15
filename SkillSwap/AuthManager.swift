//
//  AuthManager.swift
//  SkillSwap
//
//  Created by mac on 07/05/1448 AH.
//
import Foundation
import Supabase
import Combine

@MainActor
final class AuthManager: ObservableObject {

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = true

    func checkSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await AuthDiagnostics.trace("sessionRestoration") {
                try await SupabaseManager.client.auth.session
            }
            isAuthenticated = true
        } catch {
            isAuthenticated = false
        }
    }

    func didSignIn() {
        isAuthenticated = true
    }

    func signOut() async throws {
        try await SupabaseManager.client.auth.signOut()
        isAuthenticated = false
    }
}
