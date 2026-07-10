//
//  PantryTheme.swift
//  Pantry Link IOS
//
//  SwiftUI port of ui/theme/Color.kt + Theme.kt. The Android app forces the light
//  "organic" palette (dynamicColor = false), so we sample those exact HEX codes.
//  The "Liquid Glass" styling from the brief is implemented with the REAL iOS 26 API
//  (`.glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glassProminent)`), not the
//  fabricated `Material.liquidGlass`.
//

import SwiftUI
import UIKit

private extension UIColor {
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Resolves to `light` in Light Mode and `dark` in Dark Mode, so the entire app
    /// (which reads these semantic colors) adapts automatically to the system appearance.
    /// The `light` values are the exact HEX codes sampled from the Android palette (Color.kt);
    /// the `dark` values are hand-tuned counterparts with matching hue and adequate contrast.
    private static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    // Forest green. Deep in light; brightened in dark so it stays legible both as a
    // white-on-green button fill and as accent/heading text on a dark background.
    static let pantryPrimary          = adaptive(light: 0x2C5E43, dark: 0x3E9B6C)
    static let pantryPrimaryLight     = adaptive(light: 0xF4FAF6, dark: 0x14261C)
    static let pantryPrimaryContainer = adaptive(light: 0xD3E7DD, dark: 0x1E3A2B)
    static let pantryEmerald          = adaptive(light: 0x3B855F, dark: 0x53B183)
    static let pantrySecondary        = adaptive(light: 0x536A5F, dark: 0x9DB0A6)  // Charcoal sage-gray
    static let pantrySecondaryContainer = adaptive(light: 0xF0EBE3, dark: 0x2A2E2B)
    static let pantryTertiary         = adaptive(light: 0xD47A5C, dark: 0xE0947A)  // Terracotta peach
    static let pantryTertiaryContainer  = adaptive(light: 0xF6E7DF, dark: 0x3A2A22)
    static let pantryBackground       = adaptive(light: 0xFAF8F5, dark: 0x121513)  // Oatmeal cream / near-black
    static let pantrySurface          = adaptive(light: 0xFFFFFF, dark: 0x1E211F)  // Card surface
    static let pantryTextDark         = adaptive(light: 0x1E2622, dark: 0xEDF1EE)  // Primary text
    static let pantryTextMuted        = adaptive(light: 0x5A6961, dark: 0x9BA8A0)  // Secondary text
    static let pantryBorder           = adaptive(light: 0xE2E8F0, dark: 0x333935)  // Card hairline
    static let pantryDivider          = adaptive(light: 0xF1F5F9, dark: 0x2A2F2C)
    static let pantryFieldFill        = adaptive(light: 0xF8FAFC, dark: 0x2A2E2B)  // Text-field background
    static let pantryInfo             = adaptive(light: 0x1976D2, dark: 0x5AB0F0)  // Info/cold-storage blue (brightened for dark)
}

// MARK: - Liquid Glass helpers (real iOS 26 API)

extension View {
    /// A translucent Liquid Glass panel (floating control / notification layer). Uses the real
    /// `.glassEffect` and falls back to a solid surface under Reduce Transparency (see pantryGlass).
    func pantryGlassCard(cornerRadius: CGFloat = 24) -> some View {
        self.pantryGlass(cornerRadius: cornerRadius)
    }

    /// A subtly tinted interactive glass surface for chips / toggles.
    func pantryGlassChip(tint: Color, selected: Bool, cornerRadius: CGFloat = 12) -> some View {
        self.pantryGlass(tint: selected ? tint.opacity(0.35) : nil, interactive: true, cornerRadius: cornerRadius)
    }
}

/// The PantryLink logo as a clean, rounded, softly-shadowed badge — avoids the "clunky
/// white square" look of the raw asset when placed on colored surfaces.
struct PantryLogo: View {
    var size: CGFloat = 56
    var body: some View {
        // Clip the artwork itself to the rounded shape. Previously the square logo asset sat on a
        // rounded white background without being clipped, so its square corners poked past the
        // curve — the "rounded but pointy corners" look. Clipping removes that.
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous) // Apple squircle ratio
        Image("app_logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.pantryBorder.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: size * 0.09, y: 2)
    }
}

/// The gradient background the auth gate and workspaces sit on
/// (Kotlin: verticalGradient(background → primary @ 5%)).
struct PantryBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.pantryBackground, Color.pantryPrimary.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
