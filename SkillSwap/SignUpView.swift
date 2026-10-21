//
//  SignUpView.swift
//  SkillSwap
//

import SwiftUI
import Supabase

// MARK: - Focus Fields
// File-level (not nested and private) so PasswordInput can share the same focus state.

fileprivate enum SignUpField: Hashable {
    case fullName
    case email
    case password
    case confirmPassword
}

struct SignUpView: View {

    // MARK: - State

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var showPassword = false
    @State private var showConfirmPassword = false

    // MARK: - Registration State

    @State private var isLoading = false
    @State private var activeAlert: SignUpAlert?

    @EnvironmentObject private var authManager: AuthManager

    /// One alert at a time (SwiftUI can't reliably stack two `.alert`s
    /// on the same view).
    private enum SignUpAlert: Identifiable {

        case failed(String)
        case confirmEmail

        var id: String {
            switch self {
            case .failed(let message): return "failed-\(message)"
            case .confirmEmail: return "confirm-email"
            }
        }

        var title: String {
            switch self {
            case .failed: return "Sign Up Failed"
            case .confirmEmail: return "Almost there!"
            }
        }

        var message: String {
            switch self {
            case .failed(let message):
                return message
            case .confirmEmail:
                return "We've sent a confirmation link to your university email. Open it to activate your account, then log in."
            }
        }
    }

    // MARK: - Navigation

    /// What "Log In" should do.
    /// • LoginView passes a closure that simply closes Sign Up,
    ///   so you land back on the Login screen it came from.
    /// • If Sign Up was opened from anywhere else (no closure),
    ///   it opens LoginView itself.
    var onLogIn: (() -> Void)? = nil

    @State private var showLogin = false

    @FocusState private var focusedField: SignUpField?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Colors

    private let cream = Color(
        red: 0.98,
        green: 0.97,
        blue: 0.95
    )

    // MARK: - Validation

    private var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        let parts = trimmedEmail.split(
            separator: "@",
            omittingEmptySubsequences: false
        )

        guard parts.count == 2 else {
            return false
        }

        return !parts[0].isEmpty
            && parts[1].contains(".")
            && !parts[1].hasPrefix(".")
            && !parts[1].hasSuffix(".")
            && !trimmedEmail.contains(" ")
    }

    private var isPasswordLongEnough: Bool {
        password.count >= 8
    }

    private var passwordsMatch: Bool {
        password == confirmPassword
    }

    private var isFormValid: Bool {
        !trimmedFullName.isEmpty
        && isEmailValid
        && isPasswordLongEnough
        && !confirmPassword.isEmpty
        && passwordsMatch
    }

    private var canSubmit: Bool {
        isFormValid && !isLoading
    }

    // MARK: - Body

    var body: some View {

        ZStack(alignment: .topTrailing) {

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
                            .font(
                                .system(
                                    size: 12,
                                    weight: .heavy
                                )
                            )
                            .tracking(3)
                            .foregroundStyle(Theme.mutedStone)

                        Text("Join the\ncurious.")
                            .font(
                                .system(
                                    size: 52,
                                    weight: .black
                                )
                            )
                            .tracking(-2)
                            .foregroundStyle(Theme.charcoal)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .accessibilityAddTraits(.isHeader)

                        Text(
                            "Your next skill is just a student away."
                        )
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.mutedStone)
                    }

                    // MARK: - Registration Form

                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: University Email

                        // MARK: Full Name

                        VStack(alignment: .leading, spacing: 8) {

                            Text("Full Name")
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 12) {

                                Image(systemName: "person")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)

                                TextField(
                                    "Enter your full name",
                                    text: $fullName
                                )
                                .textContentType(.name)
                                .focused($focusedField, equals: .fullName)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .email
                                }
                            }
                            .padding(16)
                            .background(Theme.surface.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        // MARK: University Email

                        VStack(alignment: .leading, spacing: 8) {

                            Text("University Email")
                                .font(
                                    .system(
                                        size: 14,
                                        weight: .semibold
                                    )
                                )

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
                                .focused(
                                    $focusedField,
                                    equals: .email
                                )
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }
                            }
                            .padding(16)
                            .background(Theme.surface.opacity(0.9))
                            .clipShape(
                                RoundedRectangle(cornerRadius: 16)
                            )

                            if !trimmedEmail.isEmpty
                                && !isEmailValid
                                && focusedField != .email {

                                Text("Enter a valid email, like name@university.edu.sa.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }

                        // MARK: Password

                        VStack(alignment: .leading, spacing: 8) {

                            Text("Password")
                                .font(
                                    .system(
                                        size: 14,
                                        weight: .semibold
                                    )
                                )

                            HStack(spacing: 12) {

                                PasswordInput(
                                    placeholder: "Create a password",
                                    text: $password,
                                    isVisible: showPassword,
                                    focus: $focusedField,
                                    field: .password,
                                    submitLabel: .next,
                                    onSubmit: {
                                        focusedField = .confirmPassword
                                    }
                                )

                                Button {
                                    showPassword.toggle()
                                    keepFocus(on: .password)
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
                            .clipShape(
                                RoundedRectangle(cornerRadius: 16)
                            )

                            Text("Use at least 8 characters.")
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    !password.isEmpty && !isPasswordLongEnough
                                    ? Color.red
                                    : Color.secondary
                                )
                        }

                        // MARK: Confirm Password

                        VStack(alignment: .leading, spacing: 8) {

                            Text("Confirm Password")
                                .font(
                                    .system(
                                        size: 14,
                                        weight: .semibold
                                    )
                                )

                            HStack(spacing: 12) {

                                PasswordInput(
                                    placeholder: "Confirm your password",
                                    text: $confirmPassword,
                                    isVisible: showConfirmPassword,
                                    focus: $focusedField,
                                    field: .confirmPassword,
                                    submitLabel: .done,
                                    onSubmit: {
                                        focusedField = nil
                                    }
                                )

                                Button {
                                    showConfirmPassword.toggle()
                                    keepFocus(on: .confirmPassword)
                                } label: {

                                    Image(
                                        systemName: showConfirmPassword
                                        ? "eye.slash"
                                        : "eye"
                                    )
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    showConfirmPassword
                                    ? "Hide confirmation password"
                                    : "Show confirmation password"
                                )
                            }
                            .padding(16)
                            .background(Theme.surface.opacity(0.9))
                            .clipShape(
                                RoundedRectangle(cornerRadius: 16)
                            )

                            if !confirmPassword.isEmpty
                                && !passwordsMatch {

                                Text("Passwords don't match.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    // Lock the fields while a sign-up request is running.
                    .disabled(isLoading)

                    // MARK: - Actions & Footer
                    // Grouped in their own VStack so they sit close together,
                    // instead of inheriting the 28pt spacing used between sections.

                    VStack(spacing: 14) {

                        // MARK: - Create Account Button

                        Button {
                            register()
                        } label: {

                            HStack {

                                Text(isLoading ? "Creating Account…" : "Create Account")

                                Spacer()

                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.up.right")
                                }
                            }
                            .font(
                                .system(
                                    size: 17,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(.white)
                            .padding(20)
                            .background(
                                canSubmit
                                ? Theme.primaryAction
                                : Color.gray.opacity(0.5)
                            )
                            .clipShape(
                                RoundedRectangle(cornerRadius: 20)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .animation(.easeInOut(duration: 0.2), value: canSubmit)

                        // MARK: - Login Link

                        HStack(spacing: 4) {

                            Text("Already have an account?")
                                .foregroundStyle(Theme.mutedStone)

                            Button("Log In") {

                                focusedField = nil

                                if let onLogIn {
                                    onLogIn()
                                } else {
                                    showLogin = true
                                }
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.charcoal)
                        }
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)

                        // MARK: - Footer

                        Text(
                            "Only verified university students can join SkillSwap."
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
        // The screen uses a fixed cream background and white fields,
        // so keep text and controls in light-mode colors even when the
        // device is in Dark Mode (otherwise text turns white on cream).
        .toolbar(.hidden, for: .navigationBar)

        // Used only when Sign Up wasn't opened from LoginView.
        .fullScreenCover(isPresented: $showLogin) {
            NavigationStack {
                LoginView()
            }
        }

        // MARK: - Alerts

        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { if !$0 { activeAlert = nil } }
            ),
            presenting: activeAlert
        ) { alert in

            Button("OK", role: .cancel) {
                // After confirming the email prompt, return to where
                // Sign Up was opened from (Login or Onboarding).
                if case .confirmEmail = alert {
                    if let onLogIn {
                        onLogIn()
                    } else {
                        dismiss()
                    }
                }
            }

        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Registration

    /// Called by the Create Account button.
    private func register() {

        focusedField = nil

        guard canSubmit else { return }

        Task {
            await registerStudent()
        }
    }

    private func registerStudent() async {

        guard canSubmit else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // Pass the full name as Supabase Auth user metadata so it can be
            // written into the student's profile (via the client backfill in
            // ProfileService, and/or the recommended handle_new_user trigger).
            let response = try await SupabaseManager.client.auth.signUp(
                email: trimmedEmail,
                password: password,
                data: ["full_name": .string(trimmedFullName)]
            )

            // Clear the sensitive fields after the request.
            password = ""
            confirmPassword = ""

            if response.session != nil {
                // Email confirmation is off — the student is signed in.
                await authManager.checkSession()
            } else {
                // Email confirmation is on — prompt them to confirm.
                activeAlert = .confirmEmail
            }

        } catch {
            activeAlert = .failed(friendlyMessage(for: error))
        }
    }

    /// Turns Supabase's technical errors into messages a student understands.
    private func friendlyMessage(for error: Error) -> String {

        let raw = error.localizedDescription.lowercased()

        if raw.contains("already registered")
            || raw.contains("already been registered")
            || raw.contains("user already") {
            return "An account with this email already exists. Try logging in instead."
        }

        if raw.contains("password") && raw.contains("weak") {
            return "Please choose a stronger password."
        }

        if raw.contains("invalid") && raw.contains("email") {
            return "That email address doesn't look right. Please check it and try again."
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

    // MARK: - Helpers

    /// Swapping SecureField ↔ TextField replaces the view, which drops focus.
    /// Re-focus on the next run loop so the keyboard stays up.
    private func keepFocus(on field: SignUpField) {
        Task { @MainActor in
            focusedField = field
        }
    }
}

// MARK: - Reusable Password Input

private struct PasswordInput: View {

    let placeholder: String

    @Binding var text: String

    let isVisible: Bool

    var focus: FocusState<SignUpField?>.Binding
    let field: SignUpField

    let submitLabel: SubmitLabel
    let onSubmit: () -> Void

    var body: some View {

        Group {

            if isVisible {

                TextField(placeholder, text: $text)
                    .textContentType(.newPassword)

            } else {

                SecureField(placeholder, text: $text)
                    .textContentType(.newPassword)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused(focus, equals: field)
        .submitLabel(submitLabel)
        .onSubmit(onSubmit)
    }
}

// (GradientBubbleBackground removed — Login/Sign Up now use the shared,
//  subtle AtmosphericBackground, consistent with the authenticated app.)

// MARK: - Preview

#Preview("Sign Up Flow") {
    SignUpPreviewHost()
}

private struct SignUpPreviewHost: View {

    @State private var showSignUp = true

    var body: some View {

        ZStack {

            Color(
                red: 0.98,
                green: 0.97,
                blue: 0.95
            )
            .ignoresSafeArea()

            Button("Open Sign Up") {
                showSignUp = true
            }
        }
        .fullScreenCover(isPresented: $showSignUp) {

            NavigationStack {
                SignUpView()
            }
        }
        .environmentObject(AuthManager())
    }
}
