//
//  SavedStudents.swift
//  SkillSwap
//
//  Local "Saved Students" bookmarks. There is no backend table for saved
//  students yet, so this persists on-device via UserDefaults (a real local
//  save — not fabricated server data). Injected app-wide by ContentView.
//

import SwiftUI
import Combine

@MainActor
final class SavedStudentsStore: ObservableObject {

    @Published private(set) var saved: Set<String> = []
    private let legacyKey = "saved_students"
    private var userKey: String?

    /// Scope bookmarks to the signed-in student (call once the user id is known).
    /// Bookmarks are now isolated per account — one user's saves never appear
    /// under another's.
    func use(userID: String) {
        let key = "saved_students_\(userID.lowercased())"
        userKey = key
        let defaults = UserDefaults.standard
        // One-time migration: move any pre-isolation (shared) bookmarks to this
        // user, then remove the shared key so they can't leak to other accounts.
        if defaults.object(forKey: key) == nil, let legacy = defaults.stringArray(forKey: legacyKey) {
            defaults.set(legacy, forKey: key)
            defaults.removeObject(forKey: legacyKey)
        }
        saved = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func isSaved(_ id: String) -> Bool { saved.contains(id) }

    func toggle(_ id: String) {
        guard let userKey else { return }   // no-op until scoped to a user
        if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }
        UserDefaults.standard.set(Array(saved), forKey: userKey)
    }

    /// Raw stored count (may include ids not in the current roster). The UI
    /// shows the RESOLVED count (ids present in the directory) instead.
    var count: Int { saved.count }
}

// MARK: - Bookmark button (isolated tap target for cards)

struct BookmarkButton: View {
    @EnvironmentObject private var saved: SavedStudentsStore
    let studentID: String

    var body: some View {
        let on = saved.isSaved(studentID)
        Button { saved.toggle(studentID) } label: {
            Image(systemName: on ? "bookmark.fill" : "bookmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.charcoal)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove from saved" : "Save student")
    }
}

// MARK: - Saved Students destination

struct SavedStudentsView: View {
    @EnvironmentObject private var saved: SavedStudentsStore
    @EnvironmentObject private var directory: StudentDirectory
    @Environment(\.dismiss) private var dismiss

    // Local bookmarks (UserDefaults) resolved against the real directory.
    private var students: [DiscoveredStudent] { directory.students.filter { saved.isSaved($0.id) } }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if directory.isLoading && directory.students.isEmpty {
                        HStack { Spacer(); ProgressView().tint(Theme.primaryAction); Spacer() }.padding(.vertical, 40)
                    } else if students.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(students) { s in
                                NavigationLink { destination(s) } label: { row(s) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await directory.loadIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.charcoal).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Text("Saved Students").font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
        }
        .padding(.top, 4)
    }

    private func row(_ s: DiscoveredStudent) -> some View {
        HStack(spacing: 12) {
            avatar(s)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.charcoal)
                Text(s.major).font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
            }
            Spacer()
            BookmarkButton(studentID: s.id)
        }
        .padding(14)
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }

    @ViewBuilder private func avatar(_ s: DiscoveredStudent) -> some View {
        let size: CGFloat = 44
        if let url = s.avatarURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Monogram(initials: s.initials, size: size) }
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Monogram(initials: s.initials, size: size)
        }
    }

    private func destination(_ s: DiscoveredStudent) -> StudentProfileView {
        StudentProfileView(student: s)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark").font(.system(size: 26)).foregroundStyle(Theme.mutedStone)
            Text("No saved students yet").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text("Tap the bookmark on a student to save them here.")
                .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Received Kudos (real — Supabase, recipient-visible)

struct KudosReceivedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReceivedKudos] = []
    @State private var isLoading = true
    @State private var loadError = false
    private let service = ExchangeService()

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if isLoading {
                        HStack { Spacer(); ProgressView().tint(Theme.primaryAction); Spacer() }.padding(.vertical, 40)
                    } else if loadError {
                        emptyState(icon: "exclamationmark.triangle", title: "Couldn't load kudos",
                                   message: "Please try again.")
                    } else if items.isEmpty {
                        emptyState(icon: "heart", title: "No kudos yet",
                                   message: "Kudos you receive after completed exchanges will appear here.")
                    } else {
                        ForEach(items) { kudosCard($0) }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        do { items = try await service.receivedKudos(); loadError = false }
        catch { print("[Kudos] receive load failed:", error); loadError = true }
        isLoading = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.charcoal).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            Text("Kudos").font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
        }
        .padding(.top, 4)
    }

    private func kudosCard(_ k: ReceivedKudos) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar(k)
                VStack(alignment: .leading, spacing: 2) {
                    Text("From \(k.giverName)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.charcoal)
                    if let d = k.createdAt {
                        Text(d.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(Theme.Typography.meta).foregroundStyle(Theme.mutedStone)
                    }
                }
                Spacer()
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            if !k.tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(k.tags, id: \.self) { tag in
                        Text(tag).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.charcoal)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Theme.brightLavender.opacity(0.4)).clipShape(Capsule())
                    }
                }
            }
            if let m = k.message, !m.isEmpty {
                Text("“\(m)”").font(.system(size: 14)).foregroundStyle(Theme.charcoal.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    @ViewBuilder private func avatar(_ k: ReceivedKudos) -> some View {
        let size: CGFloat = 40
        if let url = k.giverAvatarURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Monogram(initials: k.giverInitials, size: size) }
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Monogram(initials: k.giverInitials, size: size)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.mutedStone)
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
        .background(Theme.surface.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
    }
}
