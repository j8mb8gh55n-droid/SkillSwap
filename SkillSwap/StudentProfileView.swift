//
//  StudentProfileView.swift
//  SkillSwap
//

import SwiftUI

struct StudentProfileView: View {

    // MARK: - Student Information

    let name: String
    let major: String
    let teaches: String
    let wantsToLearn: String
    let availability: String
    let initials: String
    let bannerColors: [Color]

    /// Shared profile image source (same reference the student card uses).
    /// nil → existing gradient header + initials.
    var imageURL: String? = nil
    /// ⚠️ TEMPORARY TEST ONLY — bundled asset name. Remove to revert.
    var localImageName: String? = nil

    /// Present when opened from real discovery — carries the real profile id and
    /// full skill lists (used for display + Phase C exchange requests).
    var discovered: DiscoveredStudent? = nil

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // Verified aggregate kudos count (Phase D1) — counts only, via RPC.
    @State private var kudosCount: Int?
    // Verified statistics & achievements (Phase D2) — counts only, via RPC.
    @State private var stats: StudentStats?
    private let exchangeService = ExchangeService()

    // US5: the viewed student's REAL saved availability (fetched on open).
    private enum AvailabilityPhase { case loading, loaded, failed }
    @State private var availabilityPhase: AvailabilityPhase = .loading
    @State private var availabilitySlots: [AvailabilitySlot] = []
    private let discoveryService = StudentDiscoveryService()

    // MARK: - Colors (adaptive — map to Theme so dark mode coheres)

    private let cream = Theme.warmIvory   // adaptive screen background
    private let ink = Theme.ink           // adaptive high-contrast text

    // MARK: - Body

    var body: some View {

        ZStack {

            cream
                .ignoresSafeArea()

            ScrollView {

                VStack(alignment: .leading, spacing: 0) {

                    profileBanner

                    profileInformation

                    VStack(alignment: .leading, spacing: 24) {

                        aboutSection

                        teachingSection

                        learningSection

                        availabilitySection

                        statsSection

                        achievementsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .safeAreaInset(edge: .bottom) {
            exchangeButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let id = discovered?.id {
                kudosCount = try? await exchangeService.kudosCount(studentID: id)
                stats = try? await exchangeService.studentStats(studentID: id)
                await loadAvailability(studentID: id)
            }
        }
    }

    // MARK: - Shared image source

    private var photoURL: URL? { imageURL.flatMap(URL.init(string:)) }
    private var hasPhoto: Bool { localImageName != nil || photoURL != nil }

    /// Gradient header fallback (also used while a remote image loads/fails).
    /// No decorative circles — keeps the shorter header clean.
    private var bannerGradient: some View {
        LinearGradient(colors: bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Softly blurred profile photo for the header (over-scaled → no edges).
    @ViewBuilder private var bannerVisual: some View {
        if let localImageName {                       // ⚠️ TEMP TEST
            Image(localImageName).resizable().scaledToFill().scaleEffect(1.1).blur(radius: 28)
        } else if let photoURL {
            AsyncImage(url: photoURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill().scaleEffect(1.1).blur(radius: 28) }
                else { bannerGradient }
            }
        } else {
            bannerGradient
        }
    }

    /// Sharp profile photo (or gradient + initials) for the circular avatar.
    @ViewBuilder private var avatarVisual: some View {
        if let localImageName {                       // ⚠️ TEMP TEST
            Image(localImageName).resizable().scaledToFill()
        } else if let photoURL {
            AsyncImage(url: photoURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { avatarGradientFallback }
            }
        } else {
            avatarGradientFallback
        }
    }

    private var avatarGradientFallback: some View {
        ZStack {
            LinearGradient(colors: bannerColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials).font(.system(size: 28, weight: .black)).foregroundStyle(.white)
        }
    }

    // MARK: - Profile Banner

    private var profileBanner: some View {

        ZStack(alignment: .topLeading) {

            bannerVisual
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipped()
            .mask {

                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            Button {
                dismiss()
            } label: {

                Image(systemName: "arrow.left")
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface.opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 56)
        }
        .frame(height: 200)
    }

    // MARK: - Profile Information

    private var profileInformation: some View {

        VStack(alignment: .leading, spacing: 12) {

            avatarVisual
                .frame(width: 94, height: 94)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .padding(.top, -52)

            Text(name)
                .font(.system(size: 31, weight: .black))
                .tracking(-0.8)

            Text(major)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                    Text("SkillSwap Student")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Color.purple.opacity(0.09))
                .clipShape(Capsule())

                if let c = kudosCount {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                        Text("\(c) Kudos")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.charcoal)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Color.pink.opacity(0.1))
                    .clipShape(Capsule())
                }

                if discovered != nil {
                    HStack(spacing: 6) {
                        Circle().fill(recipientStatus.tint).frame(width: 8, height: 8)
                        Text(recipientStatus.label)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.charcoal)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(recipientStatus.tint.opacity(0.3))
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    // Phase D5: the viewed student's availability status (defaults to open).
    private var recipientStatus: AvailabilityStatus { AvailabilityStatus.from(discovered?.availabilityStatus) }
    /// Sample profiles (no `discovered`) are always treated as accepting.
    private var recipientAcceptsRequests: Bool { discovered == nil || recipientStatus.acceptsRequests }

    // MARK: - About Me

    private var aboutSection: some View {

        VStack(alignment: .leading, spacing: 12) {

            sectionTitle("About Me")

            Text(aboutText)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineSpacing(5)
        }
    }

    /// Real bio when available; neutral copy otherwise. Never fabricated.
    private var aboutText: String {
        if let bio = discovered?.bio, !bio.isEmpty { return bio }
        if discovered != nil { return "\(name) hasn't added a bio yet." }
        return "Hi! I'm \(name). I love sharing what I know, learning new things, and connecting with other students through SkillSwap."
    }

    // MARK: - Availability loading & formatting (US5)

    private func loadAvailability(studentID: String) async {
        availabilityPhase = .loading
        do {
            availabilitySlots = try await discoveryService.fetchAvailability(studentID: studentID)
            availabilityPhase = .loaded
        } catch {
            print("[Availability] load failed:", error)
            availabilityPhase = .failed
        }
    }

    /// "09:00:00" → "9:00 AM" (falls back to the raw value if unparseable).
    private func formatTime(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return raw }
        let period = h < 12 ? "AM" : "PM"
        let h12 = (h % 12 == 0) ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, period)
    }

    /// Ordered day abbreviations the student is available on.
    private var availabilityDaysText: String {
        availabilitySlots.map(\.day).joined(separator: " · ")
    }

    /// A single shared time window if every slot uses the same one, else nil
    /// (the per-slot list is shown instead).
    private var sharedWindowText: String? {
        let windows = Set(availabilitySlots.compactMap { slot -> String? in
            guard let s = formatTime(slot.startTime), let e = formatTime(slot.endTime) else { return nil }
            return "\(s) – \(e)"
        })
        return windows.count == 1 ? windows.first : nil
    }

    /// Real availability content for the card. Preserves the existing secondary
    /// text style; shows loading / empty / failed states (never a placeholder).
    @ViewBuilder private var availabilityContent: some View {
        let secondary = Color.secondary
        if discovered == nil {
            // Non-discovery usage (e.g. sample data) keeps its passed-in string.
            Text(availability.isEmpty ? "Not shared" : availability)
                .font(.system(size: 13)).foregroundStyle(secondary)
        } else {
            switch availabilityPhase {
            case .loading:
                Text("Loading…").font(.system(size: 13)).foregroundStyle(secondary)
            case .failed:
                Text("Couldn't load availability.").font(.system(size: 13)).foregroundStyle(secondary)
            case .loaded:
                if availabilitySlots.isEmpty {
                    Text("No availability shared yet.").font(.system(size: 13)).foregroundStyle(secondary)
                } else if let window = sharedWindowText {
                    Text(availabilityDaysText).font(.system(size: 13)).foregroundStyle(secondary)
                    Text(window).font(.system(size: 12)).foregroundStyle(secondary)
                } else {
                    // Mixed time windows — one line per slot.
                    ForEach(availabilitySlots) { slot in
                        if let s = formatTime(slot.startTime), let e = formatTime(slot.endTime) {
                            Text("\(slot.day) · \(s) – \(e)").font(.system(size: 13)).foregroundStyle(secondary)
                        } else {
                            Text(slot.day).font(.system(size: 13)).foregroundStyle(secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Teaching Skills

    private var teachingSection: some View {

        VStack(alignment: .leading, spacing: 13) {

            sectionTitle("Skills I Can Teach")

            let teachColor = Color(red: 0.87, green: 0.83, blue: 1.0)
            if let d = discovered {
                if d.teaches.isEmpty {
                    emptySkillNote("No teaching skills added yet.")
                } else {
                    ForEach(d.teaches) { skill in
                        skillCard(title: skill.name, symbol: "lightbulb.fill", color: teachColor,
                                  subtitle: SkillExperienceLevel.label(forSlug: d.teachingLevels[skill.name]))
                    }
                }
            } else {
                skillCard(title: teaches, symbol: "lightbulb.fill", color: teachColor)
            }
        }
    }

    private func emptySkillNote(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(.secondary)
    }

    // MARK: - Learning Skills

    private var learningSection: some View {

        VStack(alignment: .leading, spacing: 13) {

            sectionTitle("Skills I Want to Learn")

            let learnColor = Color(red: 1.0, green: 0.85, blue: 0.89)
            if let d = discovered {
                if d.learns.isEmpty {
                    emptySkillNote("No learning interests added yet.")
                } else {
                    ForEach(d.learns) { skill in
                        skillCard(title: skill.name, symbol: "book.closed.fill", color: learnColor)
                    }
                }
            } else {
                skillCard(title: wantsToLearn, symbol: "book.closed.fill", color: learnColor)
            }
        }
    }

    // MARK: - Availability

    private var availabilitySection: some View {

        VStack(alignment: .leading, spacing: 13) {

            sectionTitle("Availability")

            HStack(spacing: 12) {

                Image(systemName: "calendar")
                    .font(.system(size: 18))
                    .foregroundStyle(.purple)
                    .frame(width: 46, height: 46)
                    .background(
                        Color.purple.opacity(0.09)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 5) {

                    Text("Available Days")
                        .font(
                            .system(
                                size: 13,
                                weight: .semibold
                            )
                        )

                    availabilityContent
                }

                Spacer()
            }
            .padding(16)
            .background(Theme.surface)
            .clipShape(
                RoundedRectangle(cornerRadius: 20)
            )
        }
    }

    // MARK: - Verified Statistics (Phase D2)
    //
    // Only shown for a real discovered student with verified activity — a brand
    // new profile with all-zero counts shows nothing here rather than a wall of
    // zeros. Numbers come from the server-side RPC (counts only, never invented).

    @ViewBuilder private var statsSection: some View {
        if let stats, !stats.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("Verified Stats")
                VerifiedStatsGrid(stats: stats, kudosReceived: kudosCount ?? 0)
            }
        }
    }

    @ViewBuilder private var achievementsSection: some View {
        if let stats, !stats.isEmpty {
            let badges = Achievements.all(stats: stats, kudosTotal: kudosCount ?? 0)
                .filter(\.unlocked)
            if !badges.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    sectionTitle("Achievements")
                    AchievementsStrip(achievements: badges)
                }
            }
        }
    }

    // MARK: - Skill Card

    private func skillCard(
        title: String,
        symbol: String,
        color: Color,
        subtitle: String? = nil
    ) -> some View {

        HStack(spacing: 13) {

            Image(systemName: symbol)
                .font(.system(size: 19))
                .foregroundStyle(Theme.onPastel)
                .frame(width: 49, height: 49)
                .background(color)
                .clipShape(
                    RoundedRectangle(cornerRadius: 15)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.purple)
                }
            }

            Spacer()
        }
        .padding(15)
        .background(Theme.surface)
        .clipShape(
            RoundedRectangle(cornerRadius: 20)
        )
    }

    // MARK: - Section Title

    private func sectionTitle(
        _ title: String
    ) -> some View {

        Text(title)
            .font(
                .system(
                    size: 21,
                    weight: .bold
                )
            )
            .tracking(-0.4)
    }

    // MARK: - Request Exchange Button

    @ViewBuilder private var exchangeButton: some View {

        Group {
            if recipientAcceptsRequests {
                NavigationLink {
                    RequestExchangeView(
                        studentName: name,
                        studentMajor: major,
                        studentTeaches: teaches,
                        studentWantsToLearn: wantsToLearn,
                        studentInitials: initials,
                        bannerColors: bannerColors,
                        recipient: discovered
                    )
                } label: {
                    HStack {
                        Text("Request Exchange")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.white)
                    .padding(19)
                    .background(Theme.primaryAction)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            } else {
                unavailableNotice
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(cream)
    }

    // Shown instead of the request button when the student isn't accepting.
    private var unavailableNotice: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill").foregroundStyle(.secondary)
                Text("Not accepting new requests")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
            }
            Text("\(name) isn't accepting new exchange requests right now. Check back later!")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Real-student convenience init

extension StudentProfileView {
    /// Build from a real discovered student (preserves the existing layout;
    /// carries the real id + skills via `discovered`).
    init(student s: DiscoveredStudent) {
        self.init(
            name: s.name,
            major: s.major,
            teaches: s.teaches.first?.name ?? "—",
            wantsToLearn: s.learns.first?.name ?? "—",
            availability: "",
            initials: s.initials,
            bannerColors: HomeGradients.studentPair(abs(s.id.hashValue) % 4),
            imageURL: s.avatarURL,
            localImageName: nil,
            discovered: s
        )
    }
}

// MARK: - Preview

#Preview {

    NavigationStack {

        StudentProfileView(
            name: "Sara Ahmed",
            major: "Computer Science",
            teaches: "Swift Programming",
            wantsToLearn: "UI/UX Design",
            availability: "Sun, Tue",
            initials: "SA",
            bannerColors: [
                Color(
                    red: 0.73,
                    green: 0.68,
                    blue: 1.0
                ),
                Color(
                    red: 0.94,
                    green: 0.76,
                    blue: 0.94
                )
            ]
        )
    }
}
