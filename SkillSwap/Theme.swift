//
//  Theme.swift
//  SkillSwap
//
//  Centralized design tokens for the UI/UX completion sprint.
//
//  SCOPE: Use these on NEWLY created screens only. Existing approved screens
//  keep their own local constants unchanged until we do the final visual pass.
//  Values here are copied verbatim from the existing screens so new screens
//  match the established cream / lavender / pink / mint identity.
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Palette

    /// Primary app background (Login / Profile cream). Adaptive: cream in light,
    /// near-black in dark (matches warmIvory so legacy screens cohere in dark).
    static let cream       = Color(lightHex: 0xFAF7F2, darkHex: 0x121212)
    /// Slightly warmer cream used by Home / Explore / Exchange (adaptive).
    static let creamWarm   = Color(lightHex: 0xFBFAF7, darkHex: 0x161618)

    static let lavender      = Color(red: 0.79, green: 0.72, blue: 1.00)
    static let lavenderSoft  = Color(red: 0.85, green: 0.81, blue: 1.00)
    static let lavenderTint  = Color(red: 0.87, green: 0.83, blue: 1.00)

    static let softPink = Color(red: 1.00, green: 0.87, blue: 0.91)
    static let softMint = Color(red: 0.84, green: 0.94, blue: 0.86)
    static let peach    = Color(red: 1.00, green: 0.82, blue: 0.65)

    /// High-contrast primary text. Adaptive: near-black in light, near-white in
    /// dark. NOTE: for button *backgrounds* use `primaryAction`; for text/icons on
    /// SOLID pastel fills use `onPastel` (both below) — not `ink`.
    static let ink    = Color(lightHex: 0x1A1C21, darkHex: 0xF2F2F2)
    /// Fixed near-black for text/icons sitting on SOLID pastel fills (which stay
    /// light in both appearances), so they never become light-on-light in dark.
    static let onPastel = Color(hex: 0x242424)
    /// Expressive accent (legacy — used by not-yet-migrated screens).
    static let accent = Color.purple

    // MARK: - Editorial Palette (Soft Editorial Modernism)
    // Signature tokens for migrated screens. Neutral-first: forestGreen is
    // reserved for primary actions / emphasis; sage & lavender are atmospheric
    // accents used sparingly.

    // Adaptive neutral system (light / dark). Pastel accent tokens below stay
    // fixed — they are decorative and read well on both appearances.
    static let warmIvory    = Color(lightHex: 0xFAF9F7, darkHex: 0x121212)  // primary background
    static let softCream    = Color(lightHex: 0xF0EEE7, darkHex: 0x1C1C1E)  // secondary surface
    static let forestGreen  = Color(hex: 0x243D32)   // legacy accent (being retired)
    static let olive        = Color(hex: 0x818B70)   // supporting accent
    static let sage         = Color(hex: 0xBCC8B7)   // gentle atmosphere
    static let dustyLavender = Color(hex: 0xC9BED8)  // secondary atmosphere
    static let lavenderMist = Color(hex: 0xEAE5F0)   // soft atmospheric background
    static let charcoal     = Color(lightHex: 0x242424, darkHex: 0xF2F2F2)  // primary text
    static let mutedStone   = Color(lightHex: 0x858585, darkHex: 0x9A9A9A)  // secondary text
    static let hairline     = Color(lightHex: 0x242424, darkHex: 0xFFFFFF).opacity(0.08)

    // Neutral system tokens (gray-based UI; pastel cards stay expressive).
    static let primaryAction   = Color(lightHex: 0x242424, darkHex: 0x3A3A3C)  // dark buttons
    static let neutralSurface  = Color(lightHex: 0xEFEEEC, darkHex: 0x2C2C2E)  // segmented/track
    static let neutralSelected = Color(lightHex: 0xFFFFFF, darkHex: 0x48484A)  // selected segment
    static let surface         = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)  // card surface
    static let surfaceSoft     = Color(lightHex: 0xFFFFFF, darkHex: 0x242426)  // secondary card

    // Bright pastel accents — Soft Chromatic cards & atmosphere.
    static let mint            = Color(hex: 0xBCE8D7)
    static let freshSage       = Color(hex: 0xB8D4B5)
    static let brightLavender  = Color(hex: 0xD8C5F4)
    static let lilac           = Color(hex: 0xE6D7FF)
    static let blush           = Color(hex: 0xF6C8DC)
    static let softPeach       = Color(hex: 0xFFD9C4)
    static let powderBlue      = Color(hex: 0xCBD6EC)
    static let periwinkle      = Color(hex: 0xC3C7EE)

    // MARK: - Typography
    // Native only: New York via `.serif` for editorial moments; SF Pro (default)
    // for functional text. Functional styles use text styles so they scale with
    // Dynamic Type; serif display sizes are fixed and degrade via scale factor.

    enum Typography {
        static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static let hero       = serif(42)   // reserved; Home now SF-first
        static let titleSerif = serif(27)
        // Modern SF display headlines (Soft Chromatic direction)
        static let displayLarge = Font.system(size: 30, weight: .bold)
        static let display      = Font.system(size: 24, weight: .bold)
        static let title    = Font.system(.title3).weight(.bold)
        static let headline = Font.system(.headline)
        static let body     = Font.system(.subheadline)
        static let callout  = Font.system(.footnote)
        static let meta     = Font.system(.caption)
        static let kicker   = Font.system(.caption2).weight(.semibold)
    }

    // MARK: - Motion
    // Restrained easing; minimal spring overshoot. Callers gate on Reduce Motion.

    enum Motion {
        static let standard = Animation.easeOut(duration: 0.35)
        static let gentle   = Animation.spring(response: 0.42, dampingFraction: 0.9)
        static let fade     = Animation.easeInOut(duration: 0.25)
    }

    // MARK: - Corner Radius

    enum Radius {
        static let hero:  CGFloat = 28
        static let large: CGFloat = 26
        static let card:  CGFloat = 24
        static let tile:  CGFloat = 20
        static let small: CGFloat = 14
    }

    // MARK: - Spacing

    enum Spacing {
        static let screenH: CGFloat = 20   // horizontal screen padding
        static let section: CGFloat = 28   // between major sections
        static let card:    CGFloat = 18   // inside cards
    }

    // MARK: - Gradients

    /// A soft two-stop gradient from any accent color (for banners / avatars).
    static func banner(_ colors: [Color]) -> LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Screen Styling

private struct SkillSwapScreenModifier: ViewModifier {

    var background: Color = Theme.creamWarm

    func body(content: Content) -> some View {
        ZStack {
            background.ignoresSafeArea()
            content
        }
    }
}

extension View {
    /// Applies the standard SkillSwap screen background + light appearance.
    /// Use on NEW screens only.
    func skillSwapScreen(background: Color = Theme.creamWarm) -> some View {
        modifier(SkillSwapScreenModifier(background: background))
    }
}

// MARK: - Hex Color

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8)  & 0xff) / 255,
            blue:  Double( hex        & 0xff) / 255,
            opacity: opacity
        )
    }

    /// Appearance-adaptive color: resolves to `lightHex` in Light Mode and
    /// `darkHex` in Dark Mode (via a dynamic UIColor provider).
    init(lightHex: UInt, darkHex: UInt) {
        self = Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? darkHex : lightHex
            return UIColor(
                red:   CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8)  & 0xff) / 255,
                blue:  CGFloat( hex        & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Atmosphere Tones (per-tab accent for AtmosphericBackground)

enum AtmosphereTone {
    case sage, lavender, cream, green, mist

    var primary: Color {
        switch self {
        case .sage:     return Theme.sage
        case .lavender: return Theme.dustyLavender
        case .cream:    return Theme.softCream
        case .green:    return Theme.olive
        case .mist:     return Theme.lavenderMist
        }
    }

    var secondary: Color {
        switch self {
        case .sage:     return Theme.olive
        case .lavender: return Theme.lavenderMist
        case .cream:    return Theme.olive
        case .green:    return Theme.sage
        case .mist:     return Theme.dustyLavender
        }
    }
}
