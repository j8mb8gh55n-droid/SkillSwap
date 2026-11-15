//
//  SettingsView.swift
//  SkillSwap
//
//  Settings hub, reached via the gear in ProfileView. New screens use the
//  shared Theme/components.
//
//  Real (🟢): Log Out (Supabase signOut), Change Password (auth.update),
//             account email/info (from the live session), Contact Support (mailto).
//  Local (🟠): notification toggles, profile-visibility toggle (persisted on device).
//  Prototype (⚪️): Appearance theme switch, Blocked Users, Report a Problem,
//             Help articles, Privacy Policy / Terms text, Delete Account.
//  See DATA_SOURCES.md.
//

import SwiftUI
import Supabase

struct SettingsView: View {

    @ObservedObject var store: ProfileStore
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var showLogoutConfirm = false
    @State private var isLoggingOut = false

    // Device-local preferences (functional, not synced).
    @AppStorage("notify_requests")  private var notifyRequests = true
    @AppStorage("notify_sessions")  private var notifySessions = true
    @AppStorage("notify_community") private var notifyCommunity = false
    @AppStorage("notify_kudos")     private var notifyKudos = true
    @State private var discoverable: Bool?
    @State private var isUpdatingDiscoverability = false
    @State private var discoverabilityError: String?
    private let profileService = ProfileService()
    @AppStorage("appAppearance")    private var appearancePref = AppAppearance.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                ScreenHeader(title: "Settings", dismiss: dismiss)

                accountGroup
                notificationsGroup
                appearanceGroup
                privacyGroup
                helpGroup
                aboutGroup
                dangerGroup
            }
            .padding(.horizontal, Theme.Spacing.screenH)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            email = (try? await SupabaseManager.client.auth.session.user.email) ?? ""
        }
        .task { await loadDiscoverability() }
        .confirmationDialog("Log out of SkillSwap?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { Task { await logOut() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Account

    private var accountGroup: some View {
        SettingsGroup("Account") {
            SettingsNavRow(icon: "person.crop.circle", tint: Theme.lavenderSoft,
                           title: "Account Information",
                           subtitle: store.fullName.isEmpty ? "Your profile details" : store.fullName) {
                AccountInfoView(store: store, email: email)
            }
            Divider().padding(.leading, 64)
            SettingsValueRow(icon: "envelope", tint: Theme.softPink,
                             title: "Email", value: email.isEmpty ? "—" : email)
            Divider().padding(.leading, 64)
            SettingsNavRow(icon: "key", tint: Theme.softMint, title: "Change Password") {
                ChangePasswordView()
            }
        }
    }

    // MARK: Notifications

    private var notificationsGroup: some View {
        SettingsGroup("Notifications") {
            SettingsToggleRow(icon: "bell", tint: Theme.lavenderSoft, title: "Exchange requests", isOn: $notifyRequests)
            Divider().padding(.leading, 64)
            SettingsToggleRow(icon: "calendar", tint: Theme.softPink, title: "Session reminders", isOn: $notifySessions)
            Divider().padding(.leading, 64)
            SettingsToggleRow(icon: "person.3", tint: Theme.softMint, title: "Community activity", isOn: $notifyCommunity)
            Divider().padding(.leading, 64)
            SettingsToggleRow(icon: "heart", tint: Theme.peach, title: "Kudos received", isOn: $notifyKudos)
        }
    }

    // MARK: Appearance

    private var appearanceGroup: some View {
        SettingsGroup("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Appearance", selection: $appearancePref) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                SubtleNote(text: "Choose how SkillSwap looks. System follows your device setting.")
            }
            .padding(16)
        }
    }

    // MARK: Privacy & Safety

    private func loadDiscoverability() async {
        guard !isUpdatingDiscoverability else { return }
        isUpdatingDiscoverability = true
        defer { isUpdatingDiscoverability = false }
        discoverabilityError = nil
        do {
            discoverable = try await profileService.fetchDiscoverability()
        } catch {
            discoverabilityError = "Couldn’t load your discoverability preference."
        }
    }

    private func saveDiscoverability(_ value: Bool) async {
        guard !isUpdatingDiscoverability, discoverable != value else { return }
        isUpdatingDiscoverability = true
        defer { isUpdatingDiscoverability = false }
        discoverabilityError = nil
        do {
            discoverable = try await profileService.saveDiscoverability(value)
        } catch {
            discoverabilityError = "Couldn’t confirm the change. Reload to check your saved preference."
        }
    }

    private var privacyGroup: some View {
        SettingsGroup("Privacy & Safety") {
            VStack(alignment: .leading, spacing: 8) {
                if let discoverable {
                    SettingsToggleRow(icon: "eye", tint: Theme.lavenderSoft,
                                      title: "Discoverable in Explore",
                                      isOn: Binding(get: { discoverable }, set: { value in
                                          Task { await saveDiscoverability(value) }
                                      }))
                    .disabled(isUpdatingDiscoverability)
                } else {
                    SettingsRowLabel(icon: "eye", tint: Theme.lavenderSoft, title: "Discoverable in Explore")
                        .padding(16)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Show my profile in Explore and Home recommendations.")
                        .font(Theme.Typography.callout)
                    Text("Turning this off removes you from discovery in supported versions of SkillSwap. Signed-in students can still access your public profile through existing routes.")
                        .font(Theme.Typography.meta).foregroundStyle(.secondary)

                    if isUpdatingDiscoverability {
                        ProgressView().accessibilityLabel("Updating discoverability")
                    }
                    if let discoverabilityError {
                        Text(discoverabilityError).font(Theme.Typography.meta)
                        Button("Reload preference") { Task { await loadDiscoverability() } }
                            .disabled(isUpdatingDiscoverability)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            Divider().padding(.leading, 64)
            SettingsNavRow(icon: "hand.raised", tint: Theme.softPink, title: "Blocked Students") {
                BlockedStudentsView()
            }
            Divider().padding(.leading, 64)
            SettingsNavRow(icon: "exclamationmark.bubble", tint: Theme.softMint, title: "Report a Problem") {
                ReportProblemView()
            }
            #if DEBUG
            Divider().padding(.leading, 64)
            SettingsNavRow(icon: "flag", tint: Theme.lavenderSoft, title: "Moderator Demo") {
                ModeratorDemoView()
            }
            #endif
        }
    }

    // MARK: Help & Support

    private var helpGroup: some View {
        SettingsGroup("Help & Support") {
            SettingsNavRow(icon: "questionmark.circle", tint: Theme.lavenderSoft, title: "Help Center") {
                HelpCenterView()
            }
            Divider().padding(.leading, 64)
            Link(destination: URL(string: "mailto:support@skillswap.app")!) {
                HStack {
                    SettingsRowLabel(icon: "paperplane", tint: Theme.softPink, title: "Contact Support")
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: About

    private var aboutGroup: some View {
        SettingsGroup("About SkillSwap") {
            SettingsValueRow(icon: "info.circle", tint: Theme.lavenderSoft, title: "Version", value: appVersion)
            Divider().padding(.leading, 64)
            SettingsNavRow(icon: "lock.doc", tint: Theme.softPink, title: "Privacy Policy") {
                DocumentView(title: "Privacy Policy",
                             text: "SkillSwap respects your privacy. This is placeholder policy text for the sprint build; the full privacy policy will be published before launch.")
            }
            Divider().padding(.leading, 64)
            SettingsNavRow(icon: "doc.text", tint: Theme.softMint, title: "Terms of Use") {
                DocumentView(title: "Terms of Use",
                             text: "By using SkillSwap you agree to exchange skills respectfully. This is placeholder terms text for the sprint build; the full terms will be published before launch.")
            }
        }
    }

    // MARK: Danger zone

    private var dangerGroup: some View {
        SettingsGroup("") {
            Button { showLogoutConfirm = true } label: {
                HStack {
                    SettingsRowLabel(icon: "rectangle.portrait.and.arrow.right",
                                     tint: Color.red.opacity(0.14), title: "Log Out", titleColor: .red)
                    if isLoggingOut { ProgressView() }
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            .disabled(isLoggingOut)

            Divider().padding(.leading, 64)

            SettingsNavRow(icon: "trash", tint: Color.red.opacity(0.14),
                           title: "Delete Account", titleColor: .red) {
                DeleteAccountView()
            }
        }
    }

    // MARK: Helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func logOut() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        defer { isLoggingOut = false }
        try? await authManager.signOut()
        // On success the app root swaps to Onboarding automatically.
    }
}

// MARK: - Reusable Settings primitives

struct ScreenHeader: View {
    let title: String
    let dismiss: DismissAction
    var body: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                BackChevron()
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Text(title).font(.system(size: 28, weight: .black)).tracking(-1)
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(1)
                    .foregroundStyle(.secondary).padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        }
    }
}

struct SettingsRowLabel: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var titleColor: Color = Theme.ink
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(titleColor == .red ? .red : Theme.ink)
                .frame(width: 34, height: 34).background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct SettingsNavRow<Destination: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var titleColor: Color = Theme.ink
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                SettingsRowLabel(icon: icon, tint: tint, title: title, subtitle: subtitle, titleColor: titleColor)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(icon: icon, tint: tint, title: title)
        }
        .tint(Theme.accent)
        .padding(16)
    }
}

struct SettingsValueRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    var body: some View {
        HStack {
            SettingsRowLabel(icon: icon, tint: tint, title: title)
            Text(value).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
    }
}

// MARK: - Sub-screens

struct AccountInfoView: View {
    @ObservedObject var store: ProfileStore
    let email: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Account", dismiss: dismiss)
                SettingsGroup("Your Details") {
                    SettingsValueRow(icon: "person", tint: Theme.lavenderSoft, title: "Name",
                                     value: store.fullName.isEmpty ? "Not set" : store.fullName)
                    Divider().padding(.leading, 64)
                    SettingsValueRow(icon: "graduationcap", tint: Theme.softPink, title: "Major",
                                     value: store.major.isEmpty ? "Not set" : store.major)
                    Divider().padding(.leading, 64)
                    SettingsValueRow(icon: "envelope", tint: Theme.softMint, title: "Email",
                                     value: email.isEmpty ? "—" : email)
                }
                SubtleNote(text: "Name and major are saved to your Supabase profile. Edit them from Profile → Edit Profile.")
            }
            .padding(.horizontal, Theme.Spacing.screenH).padding(.top, 10).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var done = false

    private var canSave: Bool {
        newPassword.count >= 8 && newPassword == confirmPassword && !isSaving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Change Password", dismiss: dismiss)

                if done {
                    SubtleNote(text: "Your password has been updated.", systemImage: "checkmark.seal")
                }
                if let errorMessage {
                    SubtleNote(text: errorMessage, systemImage: "exclamationmark.triangle")
                }

                field("NEW PASSWORD", text: $newPassword, placeholder: "At least 8 characters", reveal: true)
                field("CONFIRM PASSWORD", text: $confirmPassword, placeholder: "Re-enter new password", reveal: true)

                if !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text("Passwords don’t match.").font(.system(size: 12)).foregroundStyle(.red)
                }

                PrimaryButton(title: isSaving ? "Saving…" : "Update Password",
                              systemImage: "checkmark", isEnabled: canSave, isLoading: isSaving) {
                    Task { await save() }
                }

                SubtleNote(text: "This updates your real Supabase account password for this signed-in session.")
            }
            .padding(.horizontal, Theme.Spacing.screenH).padding(.top, 10).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, placeholder: String, reveal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Image(systemName: "lock").foregroundStyle(.secondary)
                Group {
                    if showPassword { TextField(placeholder, text: text) }
                    else { SecureField(placeholder, text: text) }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 15)).padding(16).background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func save() async {
        errorMessage = nil; done = false
        guard canSave else { return }
        isSaving = true; defer { isSaving = false }
        do {
            _ = try await SupabaseManager.client.auth.update(
                user: UserAttributes(password: newPassword)
            )
            done = true
            newPassword = ""; confirmPassword = ""
        } catch {
            let raw = error.localizedDescription.lowercased()
            if raw.contains("reauthauth") || raw.contains("reauthentication") || raw.contains("session") {
                errorMessage = "For security, please log out and back in, then change your password."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ReportProblemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var submitted = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Report a Problem", dismiss: dismiss)
                if submitted {
                    SubtleNote(text: "Thanks — your report was noted locally. Connecting reports to support is coming soon.", systemImage: "checkmark.seal")
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Describe what went wrong…").font(.system(size: 14))
                            .foregroundStyle(Theme.mutedStone).padding(.horizontal, 17).padding(.top, 19)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text).font(.system(size: 14)).scrollContentBackground(.hidden)
                        .frame(height: 140).padding(.horizontal, 12).padding(.vertical, 10)
                }
                .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))

                PrimaryButton(title: "Submit Report", systemImage: "paperplane.fill",
                              isEnabled: !text.trimmingCharacters(in: .whitespaces).isEmpty) {
                    submitted = true; text = ""
                }
            }
            .padding(.horizontal, Theme.Spacing.screenH).padding(.top, 10).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    private let faqs = [
        ("How do skill exchanges work?", "Find a student in Explore, send an exchange request offering a skill of yours, and once accepted you schedule a session together."),
        ("How do I add my skills?", "Open Profile → Edit Profile and add the skills you teach and want to learn, separated by commas."),
        ("What are Kudos?", "Kudos are positive appreciations you can send after completing an exchange."),
        ("Is my profile private?", "Your profile is visible to other signed-in students so they can find exchange partners.")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Help Center", dismiss: dismiss)
                ForEach(faqs, id: \.0) { q, a in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                        Text(a).font(.system(size: 13)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
                }
            }
            .padding(.horizontal, Theme.Spacing.screenH).padding(.top, 10).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct DocumentView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: title, dismiss: dismiss)
                Text(text).font(.system(size: 14)).foregroundStyle(Theme.ink).lineSpacing(5)
                SubtleNote(text: "Placeholder document for the sprint build.")
            }
            .padding(.horizontal, Theme.Spacing.screenH).padding(.top, 10).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Delete Account", dismiss: dismiss)
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 34)).foregroundStyle(.red)
                    Text("Account deletion isn’t available yet")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("Permanently deleting your account and data is not enabled in this build. When it ships, it will require confirmation and will remove your profile, skills, and exchange history.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20).background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

                // Intentionally non-destructive: disabled control only.
                Text("Delete My Account")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.mutedStone)
                    .frame(maxWidth: .infinity).padding(18)
                    .background(Theme.neutralSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
                    .overlay(alignment: .trailing) {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.mutedStone).padding(.trailing, 18)
                    }
            }
            .padding(.horizontal, Theme.Spacing.screenH).padding(.top, 10).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .skillSwapScreen(background: Theme.cream)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        SettingsView(store: ProfileStore())
            .environmentObject(AuthManager())
    }
}
