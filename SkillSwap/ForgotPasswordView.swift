//
//  ForgotPasswordView.swift
//  SkillSwap
//
//  Batch D: REAL Supabase password recovery.
//   1) Request  — resetPasswordForEmail(email) sends a recovery email.
//   2) Reset    — verifyOTP(type: .recovery) with the emailed code, then
//                 update(user: .init(password:)) sets the new password and the
//                 user is signed in.
//
//  🟢 Real Supabase. The in-app code step requires the recovery email to
//  include the 6-digit token ({{ .Token }} in the Supabase email template). If
//  your template only sends a link, the emailed link still resets via Supabase's
//  hosted page. This screen never fakes success.
//

import SwiftUI
import Supabase

struct ForgotPasswordView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    private enum Step { case request, reset }

    @State private var step: Step = .request

    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    // MARK: Validation

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canRequest: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".") && !isLoading
    }
    private var canReset: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty
        && newPassword.count >= 8
        && newPassword == confirmPassword
        && !isLoading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                header

                if let infoMessage {
                    SubtleNote(text: infoMessage, systemImage: "envelope.badge")
                }
                if let errorMessage {
                    SubtleNote(text: errorMessage, systemImage: "exclamationmark.triangle")
                }

                switch step {
                case .request: requestStep
                case .reset:   resetStep
                }
            }
            .padding(Theme.Spacing.screenH)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AtmosphericBackground())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 42, height: 42)
                        .background(Theme.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
                Text(step == .request ? "Forgot your\npassword?" : "Set a new\npassword.")
                    .font(.system(size: 36, weight: .black)).tracking(-1.5)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step == .request
                     ? "Enter your university email and we’ll send a recovery code."
                     : "Enter the code from your email and choose a new password.")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Step 1 — Request

    private var requestStep: some View {
        VStack(alignment: .leading, spacing: 18) {

            labeledField(title: "UNIVERSITY EMAIL", symbol: "envelope") {
                TextField("Enter your university email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            PrimaryButton(title: isLoading ? "Sending…" : "Send Recovery Code",
                          systemImage: "paperplane.fill",
                          isEnabled: canRequest, isLoading: isLoading) {
                Task { await requestReset() }
            }

            Button("I already have a code") {
                errorMessage = nil
                step = .reset
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Step 2 — Reset

    private var resetStep: some View {
        VStack(alignment: .leading, spacing: 18) {

            labeledField(title: "RECOVERY CODE", symbol: "number") {
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }

            labeledField(title: "NEW PASSWORD", symbol: "lock") {
                Group {
                    if showPassword {
                        TextField("At least 8 characters", text: $newPassword)
                    } else {
                        SecureField("At least 8 characters", text: $newPassword)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            labeledField(title: "CONFIRM PASSWORD", symbol: "lock.fill") {
                Group {
                    if showPassword {
                        TextField("Re-enter your password", text: $confirmPassword)
                    } else {
                        SecureField("Re-enter your password", text: $confirmPassword)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            if !confirmPassword.isEmpty && newPassword != confirmPassword {
                Text("Passwords don’t match.")
                    .font(.system(size: 12)).foregroundStyle(.red)
            }

            PrimaryButton(title: isLoading ? "Resetting…" : "Reset Password",
                          systemImage: "checkmark",
                          isEnabled: canReset, isLoading: isLoading) {
                Task { await performReset() }
            }

            Button("Send a new code") {
                step = .request
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Field helper

    @ViewBuilder
    private func labeledField<Content: View>(
        title: String, symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(1)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                content()
            }
            .font(.system(size: 15))
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Actions

    private func requestReset() async {
        errorMessage = nil; infoMessage = nil
        guard canRequest else { return }
        isLoading = true; defer { isLoading = false }
        do {
            try await SupabaseManager.client.auth.resetPasswordForEmail(trimmedEmail)
            infoMessage = "We’ve emailed a recovery code to \(trimmedEmail). Enter it below with your new password."
            step = .reset
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func performReset() async {
        errorMessage = nil
        guard canReset else { return }
        isLoading = true; defer { isLoading = false }
        do {
            // 1) Verify the recovery code → establishes a session.
            _ = try await SupabaseManager.client.auth.verifyOTP(
                email: trimmedEmail,
                token: code.trimmingCharacters(in: .whitespaces),
                type: .recovery
            )
            // 2) Set the new password on the now-authenticated user.
            _ = try await SupabaseManager.client.auth.update(
                user: UserAttributes(password: newPassword)
            )
            // Signed in with the new password.
            await authManager.checkSession()
            dismiss()
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("token") || raw.contains("otp") || raw.contains("expired") || raw.contains("invalid") {
            return "That code is invalid or has expired. Request a new one and try again."
        }
        if raw.contains("rate") || raw.contains("too many") {
            return "Too many attempts. Please wait a minute and try again."
        }
        if raw.contains("network") || raw.contains("offline") || raw.contains("internet") {
            return "You seem to be offline. Check your connection and try again."
        }
        return error.localizedDescription
    }
}

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthManager())
}
