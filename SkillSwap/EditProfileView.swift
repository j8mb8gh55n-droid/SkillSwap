//
//  EditProfileView.swift
//  SkillSwap
//
//  Personal information only (photo, name, major, About Me), restyled to match
//  the neutral SkillSwap identity: blurred profile-photo header fading into the
//  page, compact white input fields with hairline borders, charcoal text, a
//  single charcoal "Save Changes" action that is disabled until something
//  actually changes. Skills/availability live in SkillsAvailabilityView and are
//  preserved on save (re-sent unchanged).
//

import SwiftUI
import PhotosUI
import UIKit

struct EditProfileView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ProfileStore

    @State private var name = ""
    @State private var major = ""
    @State private var bio = ""
    @State private var original = ["", "", ""]   // name, major, bio snapshot

    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var showSavedAlert = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedMajor: String { major.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBio: String { bio.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var fieldsValid: Bool { !trimmedName.isEmpty && !trimmedMajor.isEmpty }
    private var hasChanges: Bool { [trimmedName, trimmedMajor, trimmedBio] != original }
    private var canSave: Bool { fieldsValid && hasChanges && !store.isSaving }

    private var initials: String {
        let words = name.split(separator: " ")
        guard !words.isEmpty else { return "?" }
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    private let bannerColors = [Theme.brightLavender, Theme.powderBlue]

    var body: some View {
        ZStack {
            Theme.warmIvory.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 24) {
                        photoBlock
                        VStack(alignment: .leading, spacing: 18) {
                            field(label: "Full Name", text: $name, placeholder: "Enter your full name")
                            field(label: "Major", text: $major, placeholder: "e.g. Computer Science")
                            bioField
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadProfile)
        .onChange(of: photoItem) { _, item in Task { await handlePicked(item) } }
        .alert("Profile Updated!", isPresented: $showSavedAlert) {
            Button("Done") { dismiss() }
        } message: { Text("Your profile changes have been saved.") }
        .alert("Couldn't Save Profile", isPresented: Binding(
            get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
            Button("OK", role: .cancel) { store.saveError = nil }
        } message: { Text(store.saveError ?? "Please try again.") }
        .alert("Couldn't Update Photo", isPresented: Binding(
            get: { store.avatarError != nil }, set: { if !$0 { store.avatarError = nil } })) {
            Button("OK", role: .cancel) { store.avatarError = nil }
        } message: { Text(store.avatarError ?? "Please try again.") }
    }

    // MARK: - Top bar + photo

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                BackChevron().foregroundStyle(Theme.charcoal)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Spacer()
            Text("Edit Profile").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
    }

    private var photoBlock: some View {
        // Read the main-actor state here (in the isolated property getter), not
        // inside the PhotosPicker label closure.
        let uploading = store.isUploadingAvatar
        return VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    avatarView
                        .frame(width: 96, height: 96).clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    if uploading {
                        Circle().fill(.black.opacity(0.35)).frame(width: 96, height: 96)
                        ProgressView().tint(.white)
                    }
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Theme.charcoal, in: Circle())
                        .overlay(Circle().stroke(Theme.warmIvory, lineWidth: 2))
                }
            }
            .buttonStyle(.plain).accessibilityLabel("Change profile photo")

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Text("Edit Photo").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.charcoal)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    @ViewBuilder private var avatarView: some View {
        if let pickedImage {
            Image(uiImage: pickedImage).resizable().scaledToFill()
        } else if let url = store.avatarURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { initialsAvatar }
            }
        } else { initialsAvatar }
    }

    private var initialsAvatar: some View {
        ZStack {
            LinearGradient(colors: bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if name.isEmpty {
                Image(systemName: "person.fill").font(.system(size: 36)).foregroundStyle(.white)
            } else {
                Text(initials).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            }
        }
    }

    // MARK: - Fields

    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Theme.mutedStone)
            TextField(placeholder, text: text)
                .font(.system(size: 15)).foregroundStyle(Theme.charcoal)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT ME")
                .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Theme.mutedStone)
            ZStack(alignment: .topLeading) {
                if bio.isEmpty {
                    Text("Tell other students a little about yourself…")
                        .font(.system(size: 15)).foregroundStyle(Theme.mutedStone.opacity(0.7))
                        .padding(.horizontal, 16).padding(.top, 15).allowsHitTesting(false)
                }
                TextEditor(text: $bio)
                    .font(.system(size: 15)).foregroundStyle(Theme.charcoal)
                    .scrollContentBackground(.hidden)
                    .frame(height: 110).padding(.horizontal, 12).padding(.vertical, 8)
            }
            .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .onChange(of: bio) { _, v in if v.count > 250 { bio = String(v.prefix(250)) } }

            Text("\(bio.count)/250")
                .font(.system(size: 11)).foregroundStyle(Theme.mutedStone)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var saveBar: some View {
        Button { saveProfile() } label: {
            HStack {
                Text(store.isSaving ? "Saving…" : "Save Changes").font(.system(size: 15, weight: .semibold))
                Spacer()
                if store.isSaving { ProgressView().tint(.white) } else { Image(systemName: "checkmark") }
            }
            .foregroundStyle(.white).padding(18)
            .background(canSave ? Theme.primaryAction : Color.gray.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)
    }

    // MARK: - Logic

    private func loadProfile() {
        name = store.fullName; major = store.major; bio = store.bio
        original = [name.trimmingCharacters(in: .whitespacesAndNewlines),
                    major.trimmingCharacters(in: .whitespacesAndNewlines),
                    bio.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private func saveProfile() {
        guard canSave else { return }
        Task {
            let ok = await store.save(
                fullName: trimmedName, major: trimmedMajor, bio: trimmedBio,
                teachingSkills: store.teachingSkills,     // preserved unchanged
                learningSkills: store.learningSkills,
                availability: store.availability
            )
            if ok { showSavedAlert = true }
        }
    }

    private func handlePicked(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pickedImage = image
        if let jpeg = Self.downscaledJPEG(image) { _ = await store.uploadAvatar(jpeg) }
    }

    private static func downscaledJPEG(_ image: UIImage, maxEdge: CGFloat = 512) -> Data? {
        let longEdge = max(image.size.width, image.size.height)
        let scale = longEdge > maxEdge ? maxEdge / longEdge : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

#Preview {
    NavigationStack { EditProfileView(store: ProfileStore()) }
}
