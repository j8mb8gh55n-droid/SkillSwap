import SwiftUI

// MARK: - Gradient helpers

enum HomeGradients {
    /// Curated pastel pairs/triples for cards (varied, unified).
    static let pairs: [[Color]] = [
        [Theme.mint, Theme.freshSage, Theme.sage],
        [Theme.brightLavender, Theme.lilac, Theme.blush],
        [Theme.softPeach, Theme.blush, Theme.lilac],
        [Theme.mint, Theme.lilac, Theme.brightLavender],
        [Theme.blush, Theme.softPeach, Theme.lilac],
        [Theme.lilac, Theme.mint, Theme.freshSage]
    ]
    static func pair(_ i: Int) -> [Color] { pairs[i % pairs.count] }

    /// Student-card fallback palettes — lavender / soft blue / mint / peach.
    static let studentPairs: [[Color]] = [
        [Theme.brightLavender, Theme.powderBlue],
        [Theme.periwinkle, Theme.lilac],
        [Theme.mint, Theme.powderBlue],
        [Theme.softPeach, Theme.lavenderMist]
    ]
    static func studentPair(_ i: Int) -> [Color] { studentPairs[i % studentPairs.count] }

    /// Smooth multi-stop diagonal blend (no circles, continuous).
    static func soft(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Soft chromatic monogram avatar (colorful; reads on white info areas).
struct Monogram: View {
    let initials: String
    var size: CGFloat = 48
    var colors: [Color] = [Theme.mint, Theme.brightLavender]
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(Theme.charcoal)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Circle())
            
    }
}

// MARK: - Student card (gradient header → info area)

struct HomeStudentCard: View {

    enum Style { case featured, gem }

    let student: MockStudent
    let colors: [Color]
    var style: Style = .featured
    /// Optional mutual-match indicator (Explore). nil → no badge.
    var matchLabel: String? = nil

    private var isGem: Bool { style == .gem }
    // Single image source — same as the destination profile.
    private var url: URL? { student.avatarURL.flatMap(URL.init(string:)) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backgroundLayer
            // Ivory scrim: fades the atmospheric top into a readable content area.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Theme.warmIvory.opacity(0.7), location: isGem ? 0.36 : 0.42),
                    .init(color: Theme.warmIvory, location: 0.92)
                ],
                startPoint: .top, endPoint: .bottom
            )
            content.padding(isGem ? 14 : 16)

            if let matchLabel {
                // Top-LEFT, truncating, with the right side reserved for the
                // top-right bookmark so the two never overlap.
                HStack(spacing: 0) {
                    Text(matchLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.forestGreen)
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Theme.surface.opacity(0.88))
                        .clipShape(Capsule())
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            }
        }
        .frame(maxWidth: isGem ? .infinity : nil)
        .frame(width: isGem ? nil : 300, height: isGem ? 172 : 232)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
    }

    // Richer pastel fallback so the upper area never looks empty.
    private var fallbackGradient: LinearGradient {
        let a = colors[0]
        let b = colors.count > 1 ? colors[1] : colors[0]
        return LinearGradient(
            colors: [a, b, a.opacity(0.78)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Over-scaled + blurred fill so blur bleed is clipped away (no harsh edges).
    private func blurredFill(_ image: Image) -> some View {
        image.resizable().scaledToFill().scaleEffect(1.15).blur(radius: 22).opacity(0.95)
    }

    // Blurred profile image if present, otherwise the pastel gradient.
    @ViewBuilder private var backgroundLayer: some View {
        if let localImageName = student.localImageName {   // ⚠️ TEMP TEST
            blurredFill(Image(localImageName))
        } else if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image { blurredFill(image) }
                else { fallbackGradient }
            }
        } else {
            fallbackGradient
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: isGem ? 8 : 10) {
            avatar(size: isGem ? 48 : 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name)
                    .font(.system(size: isGem ? 16 : 20, weight: .bold))
                    .foregroundStyle(Theme.charcoal).lineLimit(1)
                Text(student.major)
                    .font(.system(size: isGem ? 12 : 13, weight: .medium))
                    .foregroundStyle(Theme.charcoal.opacity(0.68)).lineLimit(1)
            }
            if isGem {
                Text(student.teaches.first ?? "—")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.charcoal)
                    .lineLimit(1)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.8)).clipShape(Capsule())
            } else {
                HairlineDivider().padding(.top, 2)
                skillRow("Teaches", student.teaches.first ?? "—")
                skillRow("Wants to learn", student.learns.first ?? "—")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    @ViewBuilder private func avatar(size: CGFloat) -> some View {
        Group {
            if let localImageName = student.localImageName {   // ⚠️ TEMP TEST
                Image(localImageName).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    
            } else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Monogram(initials: student.initials, size: size) }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                
            } else {
                Monogram(initials: student.initials, size: size)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }

    private func skillRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.mutedStone)
                .frame(width: 102, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.charcoal)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Upcoming Exchange

/// A genuinely confirmed upcoming session. Supplied by a real data source;
/// nil → compact empty state. (No fabricated sessions.)
struct UpcomingSession {
    let exchangeID: String
    let skill: String
    let partnerName: String
    let partnerInitials: String
    let partnerImageURL: String?
    let partnerLocalImage: String?
    let whenText: String        // e.g. "Tomorrow · 4:00 PM"
    let format: String?         // "Online" / "In Person" when available
    let bannerColors: [Color]

    var asExchange: SkillExchange {
        SkillExchange(
            id: exchangeID, studentName: partnerName, studentMajor: "",
            initials: partnerInitials, learningSkill: skill, offeringSkill: "",
            status: .accepted, isIncoming: false, date: whenText, bannerColors: bannerColors
        )
    }
}

// (HomeUpcomingCard / UpcomingPreview removed — "Upcoming Exchanges" no longer
//  appears on Home. Upcoming sessions live in the Exchanges tab. The
//  UpcomingSession model + UpcomingSessionService are kept for reuse.)

// MARK: - Compact Home Recommendations

struct HomeRecommendationCard: View {
    let student: DiscoveredStudent
    let isMutual: Bool
    @ScaledMetric(relativeTo: .headline) private var width = 148.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DiscoveryStudentAvatar(student: student)

            Text(student.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            if isMutual {
                Label("Mutual Match", systemImage: "arrow.left.arrow.right")
                    .font(Theme.Typography.meta.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(.regular.tint(Theme.mint.opacity(0.27)), in: .capsule)
            } else if !student.major.isEmpty {
                Text(student.major).font(Theme.Typography.meta)
                    .foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .frame(width: min(width, 228), alignment: .leading)
        .background {
            GeometryReader { bounds in
                StudentCardBackground(imageURL: student.avatarURL,
                                      fallbackColors: [Theme.neutralSurface, Theme.surface],
                                      cornerRadius: Theme.Radius.tile)
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.tile)
                            .fill(Theme.warmIvory.opacity(0.43))
                    }
            }
            .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.hairline)
            .allowsHitTesting(false))
    }
}

struct HomeSkillsInDemand: View {
    @EnvironmentObject private var directory: StudentDirectory
    @Environment(\.colorScheme) private var appearance
    @ScaledMetric(relativeTo: .headline) private var tileWidth = 148.0
    @ScaledMetric(relativeTo: .headline) private var tileHeight = 96.0

    var body: some View {
        let skills = HomeSkillDemand.ranked(in: directory.students)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                EditorialSectionHeader(title: "Skills in Demand")
                if !skills.isEmpty {
                    Text("Skills students want to learn")
                        .font(Theme.Typography.meta).foregroundStyle(.secondary)
                        .accessibilityHint("Counts include discoverable students.")
                }
            }
            if !skills.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(skills.enumerated()), id: \.element.id) { index, demand in
                            NavigationLink {
                                FeaturedSkillDetailView(skill: demand.skill)
                            } label: {
                                demandTile(demand, colors: HomeGradients.pair(index))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else if directory.hasLoaded {
                Text("No learning skills listed yet.")
                    .font(Theme.Typography.callout).foregroundStyle(.secondary)
            } else if let error = directory.loadError {
                Text(error).font(Theme.Typography.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().accessibilityLabel("Loading skill demand")
            }
        }
    }

    private func demandTile(_ demand: HomeSkillDemand, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(demand.skill.name).font(.headline).lineLimit(2, reservesSpace: true)
            Text(demand.count == 1 ? "1 student" : "\(demand.count) students")
                .font(Theme.Typography.meta)
        }
        .foregroundStyle(appearance == .dark ? Theme.ink : Theme.onPastel)
        .padding(12)
        .frame(width: max(148, tileWidth), height: tileHeight, alignment: .leading)
        .background {
            ZStack {
                HomeGradients.soft(colors)
                Theme.surface.opacity(appearance == .dark ? 0.82 : 0.34)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        }
    }
}
