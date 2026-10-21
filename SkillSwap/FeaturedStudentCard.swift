//
//  FeaturedStudentCard.swift
//  SkillSwap
//

import SwiftUI

// MARK: - Card Style

enum StudentCardStyle {
    case featured
    case compact
}

// MARK: - Featured Student Card

struct FeaturedStudentCard: View {

    let name: String
    let major: String
    let teaches: String
    let wantsToLearn: String
    let availability: String

    let bannerColors: [Color]
    let initials: String

    // Defaults to Home's existing portrait card.
    var style: StudentCardStyle = .featured

    /// Optional mutual-match indicator (Explore). `nil` → no badge (existing
    /// behavior unchanged for all other call sites).
    var matchLabel: String? = nil

    private var isCompact: Bool {
        style == .compact
    }

    private var cardWidth: CGFloat? {
        isCompact ? nil : 282
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Banner

            banner

            // MARK: - Content

            VStack(alignment: .leading, spacing: isCompact ? 11 : 15) {

                avatar

                studentInformation

                skillsPanel

                availabilityRow

                profileButton
            }
            .padding(.horizontal, isCompact ? 16 : 18)
            .padding(.bottom, isCompact ? 16 : 18)
        }
        .frame(width: cardWidth)
        .frame(maxWidth: isCompact ? .infinity : nil)
        .background(Theme.surface)
        .clipShape(
            RoundedRectangle(cornerRadius: 26)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(
                    .black.opacity(0.035),
                    lineWidth: 1
                )
        }
        .shadow(
            color: .black.opacity(0.05),
            radius: 12,
            x: 0,
            y: 5
        )
    }

    // MARK: - Banner

    private var banner: some View {

        ZStack(alignment: .topTrailing) {

            LinearGradient(
                colors: bannerColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 150, height: 150)
                .offset(x: 45, y: -60)

            Circle()
                .stroke(
                    .white.opacity(0.35),
                    lineWidth: 1.5
                )
                .frame(width: 110, height: 110)
                .offset(x: -100, y: 65)

            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.75))
                .rotationEffect(.degrees(-15))
                .offset(x: -30, y: 45)

            Text("SKILLSWAP COMMUNITY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.18))
                .clipShape(Capsule())
                .padding(14)

            if let matchLabel {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 9))
                    Text(matchLabel)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surface.opacity(0.92))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            }
        }
        .frame(height: isCompact ? 85 : 112)
        .clipped()
    }

    // MARK: - Avatar

    private var avatar: some View {

        ZStack {

            Circle()
                .fill(.white)
                .frame(
                    width: isCompact ? 62 : 72,
                    height: isCompact ? 62 : 72
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: bannerColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: isCompact ? 54 : 64,
                    height: isCompact ? 54 : 64
                )

            Text(initials)
                .font(
                    .system(
                        size: isCompact ? 18 : 21,
                        weight: .black
                    )
                )
                .foregroundStyle(.white)
        }
        .frame(height: isCompact ? 35 : 42)
        .padding(.top, isCompact ? -32 : -38)
    }

    // MARK: - Student Information

    private var studentInformation: some View {

        VStack(alignment: .leading, spacing: 4) {

            Text(name)
                .font(
                    .system(
                        size: isCompact ? 18 : 20,
                        weight: .bold
                    )
                )
                .tracking(-0.5)
                .foregroundStyle(.black)

            Text(major)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Skills Panel

    private var skillsPanel: some View {

        HStack(alignment: .top, spacing: 12) {

            skillColumn(
                label: "CAN TEACH",
                value: teaches
            )

            Rectangle()
                .fill(.black.opacity(0.08))
                .frame(width: 1, height: 40)

            skillColumn(
                label: "WANTS TO LEARN",
                value: wantsToLearn
            )
        }
        .padding(isCompact ? 12 : 14)
        .frame(maxWidth: .infinity)
        .background(
            Color(
                red: 0.97,
                green: 0.97,
                blue: 0.98
            )
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 14)
        )
    }

    private func skillColumn(
        label: String,
        value: String
    ) -> some View {

        VStack(alignment: .leading, spacing: 6) {

            Text(label)
                .font(
                    .system(
                        size: 10,
                        weight: .bold
                    )
                )
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.black)
                .lineLimit(2)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    // MARK: - Availability

    private var availabilityRow: some View {

        HStack(spacing: 6) {

            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)

            Text("Available: \(availability)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Profile Button

    // MARK: - Profile Button

    private var profileButton: some View {

        NavigationLink {

            StudentProfileView(
                name: name,
                major: major,
                teaches: teaches,
                wantsToLearn: wantsToLearn,
                availability: availability,
                initials: initials,
                bannerColors: bannerColors
            )

        } label: {

            HStack(spacing: 8) {

                Spacer()

                Text("View Profile")
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))

                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.vertical, isCompact ? 12 : 14)
            .background(.black)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {

    ScrollView {

        VStack(spacing: 25) {

            FeaturedStudentCard(
                name: "Sara Ahmed",
                major: "Computer Science",
                teaches: "Swift Programming",
                wantsToLearn: "UI/UX Design",
                availability: "Sun, Tue",
                bannerColors: [
                    Color(red: 0.73, green: 0.68, blue: 1.0),
                    Color(red: 0.94, green: 0.76, blue: 0.94)
                ],
                initials: "SA",
                style: .featured
            )

            FeaturedStudentCard(
                name: "Sara Ahmed",
                major: "Computer Science",
                teaches: "Swift Programming",
                wantsToLearn: "UI/UX Design",
                availability: "Sun, Tue",
                bannerColors: [
                    Color(red: 0.73, green: 0.68, blue: 1.0),
                    Color(red: 0.94, green: 0.76, blue: 0.94)
                ],
                initials: "SA",
                style: .compact
            )
        }
        .padding(20)
    }
    .background(
        Color(
            red: 0.98,
            green: 0.97,
            blue: 0.96
        )
    )
}
