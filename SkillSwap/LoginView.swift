//
//  LoginView.swift
//  SkillSwap
//

import SwiftUI
import Supabase

struct LoginView: View {

    // MARK: - State

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false

    // MARK: - Login State

    @State private var isLoading = false
    @State private var activeAlert: LoginAlert?

    @FocusState private var focusedField: LoginField?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    private enum LoginField: Hashable {
        case email
        case password
    }

    /// One alert at a time: SwiftUI can't reliably show two `.alert`s
    /// attached to the same view.
    private enum LoginAlert: Identifiable {

        case failed(String)

        var id: String {
            switch self {
            case .failed(let message):
                return "failed-\(message)"
            }
        }

        var title: String {
            switch self {
            case .failed:
                return "Login Failed"
            }
        }

        var message: String {
            switch self {
            case .failed(let message):
                return message
            }
        }
    }

    // MARK: - Navigation

    @State private var showSignUp = false
    @State private var showForgotPassword = false

    // MARK: - Colors

    private let cream = Color(
        red: 0.98,
        green: 0.97,
        blue: 0.95
    )

    // MARK: - Validation

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        !trimmedEmail.isEmpty
        && !password.isEmpty
    }

    private var canSubmit: Bool {
        isFormValid && !isLoading
    }

    // MARK: - Body

    var body: some View {

        ZStack {

            // MARK: - Background

            AtmosphericBackground()

            // MARK: - Main Content

            ScrollView {

                VStack(alignment: .leading, spacing: 28) {

                    // MARK: - Back Button

                    Button {
                        focusedField = nil
                        dismiss()
                    } label: {

                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.charcoal)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    // MARK: - Header

                    VStack(alignment: .leading, spacing: 12) {

                        Text("SKILLSWAP")
                            .font(.system(size: 12, weight: .heavy))
                            .tracking(3)
                            .foregroundStyle(Theme.mutedStone)

                        Text("Welcome\nback.")
                            .font(.system(size: 52, weight: .black))
                            .tracking(-2)
                            .foregroundStyle(Theme.charcoal)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .accessibilityAddTraits(.isHeader)

                        Text("Ready to learn something new?")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.mutedStone)
                    }

                    // MARK: - Login Form

                    VStack(alignment: .leading, spacing: 20) {

                        // University Email

                        VStack(alignment: .leading, spacing: 8) {

                            Text("University Email")
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 12) {

                                Image(systemName: "envelope")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)

                                TextField(
                                    "Enter your university email",
                                    text: $email
                                )
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }
                            }
                            .padding(16)
                            .background(Theme.surface.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
                        }

                        // Password

                        VStack(alignment: .leading, spacing: 8) {

                            Text("Password")
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 12) {

                                Group {

                                    if showPassword {

                                        TextField(
                                            "Enter your password",
                                            text: $password
                                        )

                                    } else {

                                        SecureField(
                                            "Enter your password",
                                            text: $password
                                        )
                                    }
                                }
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit {
                                    logIn()
                                }

                                Button {
                                    showPassword.toggle()
                                    // Swapping SecureField ↔ TextField drops focus;
                                    // put it back on the next run loop.
                                    Task { @MainActor in
                                        focusedField = .password
                                    }
                                } label: {

                                    Image(
                                        systemName: showPassword
                                        ? "eye.slash"
                                        : "eye"
                                    )
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    showPassword
                                    ? "Hide password"
                                    : "Show password"
                                )
                            }
                            .padding(16)
                            .background(Theme.surface.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))

                            // Forgot Password

                            Button {
                                focusedField = nil
                                showForgotPassword = true
                            } label: {

                                Text("Forgot password?")
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundStyle(Theme.charcoal)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    // Lock the fields while a login request is running.
                    .disabled(isLoading)

                    // MARK: - Actions & Footer
                    // Grouped so they sit close together instead of
                    // inheriting the 28pt spacing used between sections.

                    VStack(spacing: 14) {

                        // MARK: - Login Button

                        Button {
                            logIn()
                        } label: {

                            HStack {

                                Text(isLoading ? "Logging In…" : "Log In")

                                Spacer()

                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.up.right")
                                }
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(20)
                            .background(
                                canSubmit ? Theme.primaryAction : Color.gray.opacity(0.5)
                            )
                            .clipShape(
                                RoundedRectangle(cornerRadius: 20)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .animation(.easeInOut(duration: 0.2), value: canSubmit)

                        // MARK: - Sign Up Link

                        HStack(spacing: 4) {

                            Text("New around here?")
                                .foregroundStyle(Theme.mutedStone)

                            Button("Create an account") {
                                focusedField = nil
                                showSignUp = true
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.charcoal)
                        }
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)

                        // MARK: - Footer

                        Text(
                            "A community built on sharing what you know."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        // Fixed cream background → keep light-mode text colors in Dark Mode.
        .toolbar(.hidden, for: .navigationBar)

        // MARK: - Navigation

        .fullScreenCover(isPresented: $showSignUp) {
            NavigationStack {
                // "Log In" on Sign Up closes it and returns here,
                // instead of stacking another LoginView on top.
                SignUpView(onLogIn: {
                    showSignUp = false
                })
            }
        }

        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
                .presentationDragIndicator(.visible)
        }

        // MARK: - Alerts

        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { if !$0 { activeAlert = nil } }
            ),
            presenting: activeAlert
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Actions

    /// Called by the Log In button and by "Go" on the keyboard.
    private func logIn() {
        focusedField = nil
        guard canSubmit else { return }

        Task {
            await loginStudent()
        }
    }

    // MARK: - Supabase Login

    // MARK: - Supabase Login

    private func loginStudent() async {

        guard canSubmit else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // Authenticate the student with Supabase
            _ = try await SupabaseManager.client.auth.signIn(
                email: trimmedEmail,
                password: password
            )

            // Clear the password after successful login
            password = ""

            // Update the app's authentication state
            await authManager.checkSession()

        } catch {
            activeAlert = .failed(friendlyMessage(for: error))
        }
    }
    /// Turns Supabase's technical errors into messages a student understands.
    private func friendlyMessage(for error: Error) -> String {

        let raw = error.localizedDescription.lowercased()

        if raw.contains("invalid login credentials") {
            return "That email and password don't match. Check them and try again."
        }

        if raw.contains("email not confirmed") {
            return "Please confirm your email first. Open the link we sent to your university inbox, then log in."
        }

        if raw.contains("offline")
            || raw.contains("network")
            || raw.contains("internet") {
            return "You seem to be offline. Check your connection and try again."
        }

        if raw.contains("rate limit") || raw.contains("too many") {
            return "Too many attempts. Wait a minute, then try again."
        }

        return error.localizedDescription
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LoginView()
    }
    .environmentObject(AuthManager())
}
