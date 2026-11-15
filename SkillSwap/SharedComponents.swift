//
//  SharedComponents.swift
//  SkillSwap
//
//  Reusable building blocks for newly created sprint screens. They mirror the
//  established visual language (rounded white cards, cream, lavender, ink) so
//  new screens stay cohesive. Existing approved screens are NOT modified to use
//  these yet — that happens in the final visual pass.
//

import SwiftUI

// MARK: - Section Header

struct SectionHeader: View {

    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rounded Card

/// White rounded container matching the app's card style.
struct RoundedCard<Content: View>: View {

    var padding: CGFloat = Theme.Spacing.card
    var cornerRadius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Skill Pill

struct SkillPill: View {

    let text: String
    var color: Color = Theme.lavenderTint

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Avatar Badge

/// Gradient circle with initials (same look as the student cards).
struct AvatarBadge: View {

    let initials: String
    var colors: [Color] = [Theme.lavender, Theme.softPink]
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(Theme.banner(colors))
                .frame(width: size, height: size)

            Text(initials)
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Primary Button

/// Ink-colored primary action button matching existing CTAs.
struct PrimaryButton: View {

    let title: String
    var systemImage: String? = "arrow.up.right"
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .foregroundStyle(.white)
            .padding(19)
            .background(isEnabled ? Theme.primaryAction : Color.gray.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Stat Tile

struct StatTile: View {

    let value: String
    let label: String
    var systemImage: String
    var color: Color = Theme.lavenderSoft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 35, height: 35)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Theme.ink)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
    }
}

// MARK: - Empty State

struct EmptyStateView: View {

    var systemImage: String = "sparkles"
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 38))
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(Theme.primaryAction)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

// MARK: - Subtle Note
//
// Used instead of loud "PROTOTYPE" badges: a quiet, honest explanation for
// actions that aren't wired to a backend yet. Never pretends success.

struct SubtleNote: View {

    let text: String
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lavenderTint.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
    }
}

// MARK: - Editorial System (Soft Editorial Modernism)
// Additive components for migrated screens. Existing components above remain
// valid for not-yet-migrated screens.

/// One reusable atmospheric background: ivory with whisper-soft radial pigment
/// near opposing edges. `progress` 0 → initial (edges only), 1 → spread inward.
/// Respects Reduce Motion (static) and uses radial falloff (no expensive blur).
struct AtmosphericBackground: View {

    var tone: AtmosphereTone = .sage   // retained for API compatibility
    var progress: CGFloat = 0          // ignored while `static` (this pass is static)
    /// Flip to false to fall back to a plain ivory background.
    var enabled: Bool = true

    var body: some View {
        if !enabled {
            Theme.warmIvory.ignoresSafeArea()
        } else {
            ZStack {
                Theme.warmIvory

                // Barely-there neutral sage wash — present but almost unnoticeable,
                // no circular boundary, no saturated color. Adapts via warmIvory.
                LinearGradient(
                    colors: [Theme.sage.opacity(0.10), .clear],
                    startPoint: .top, endPoint: .center
                )
                RadialGradient(
                    gradient: Gradient(colors: [Theme.sage.opacity(0.07), .clear]),
                    center: UnitPoint(x: 0.9, y: 0.05),
                    startRadius: 0, endRadius: 600
                )
            }
            .ignoresSafeArea()
        }
    }
}

/// Reports vertical scroll progress for the atmospheric background.
struct ScrollProgressKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Editorial section header: optional small kicker + title (serif optional) +
/// optional trailing control. Used sparingly — not every section needs a kicker.
struct EditorialSectionHeader<Trailing: View>: View {

    let title: String
    var kicker: String? = nil
    var serif: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if let kicker {
                    Text(kicker.uppercased())
                        .font(Theme.Typography.kicker).tracking(1.4)
                        .foregroundStyle(Theme.mutedStone)
                }
                Text(title)
                    .font(serif ? Theme.Typography.titleSerif : Theme.Typography.title)
                    .foregroundStyle(Theme.charcoal)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension EditorialSectionHeader where Trailing == EmptyView {
    init(title: String, kicker: String? = nil, serif: Bool = false) {
        self.init(title: title, kicker: kicker, serif: serif) { EmptyView() }
    }
}

/// Thin editorial rule.
struct HairlineDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

extension View {
    /// Consistent subtle elevation for Home surface cards.
    func softCardShadow() -> some View {
        shadow(color: .black.opacity(0.05), radius: 9, y: 4)
    }
}

// MARK: - Shared student-card background
// The single, approved blurred-photo treatment (matching Home student cards):
// a full-card, softly blurred photo that dissolves seamlessly into warm ivory
// via a multi-stop gradient — no header strip, no harsh fade line. Falls back
// to the soft pastel gradient when there is no photo. Use as a card `.background`.
struct StudentCardBackground: View {
    var imageURL: String? = nil
    var localImageName: String? = nil
    var fallbackColors: [Color] = [Theme.lavenderMist]
    var cornerRadius: CGFloat = Theme.Radius.large

    private var url: URL? { imageURL.flatMap(URL.init(string:)) }

    var body: some View {
        ZStack {
            photo
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Theme.warmIvory.opacity(0.30), location: 0.32),
                    .init(color: Theme.warmIvory.opacity(0.78), location: 0.62),
                    .init(color: Theme.warmIvory.opacity(0.96), location: 0.85),
                    .init(color: Theme.warmIvory, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder private var photo: some View {
        let colors = fallbackColors.isEmpty ? [Theme.lavenderMist] : fallbackColors
        let fallback = LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        if let localImageName {
            Image(localImageName).resizable().scaledToFill().scaleEffect(1.15).blur(radius: 24).opacity(0.95)
        } else if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill().scaleEffect(1.15).blur(radius: 24).opacity(0.95)
                } else { fallback }
            }
        } else {
            fallback
        }
    }
}

/// Forest-green primary action (reserved for meaningful primary actions).
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = "arrow.up.right"
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.Typography.headline)
                Spacer()
                if isLoading { ProgressView().tint(.white) }
                else if let systemImage { Image(systemName: systemImage) }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 17).padding(.horizontal, 20)
            .background(isEnabled ? Theme.forestGreen : Theme.mutedStone.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

/// Quiet charcoal outline action for secondary navigation.
struct SecondaryActionButton: View {
    let title: String
    var systemImage: String? = "arrow.up.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(Theme.Typography.callout.weight(.semibold))
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.charcoal)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pill Tag Row (wrapping)

/// A simple leading-aligned adaptive grid of pills.
struct SkillPillWrap: View {

    let skills: [String]
    var color: Color = Theme.lavenderTint

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90), spacing: 9, alignment: .leading)],
            alignment: .leading,
            spacing: 9
        ) {
            ForEach(skills, id: \.self) { skill in
                SkillPill(text: skill, color: color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct BackChevron: View {
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Image(systemName: layoutDirection == .rightToLeft ? "chevron.right" : "chevron.left")
            .font(.system(size: 16, weight: .semibold))
    }
}
