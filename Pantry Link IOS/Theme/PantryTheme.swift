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

    // Sampled from Color.kt (organic hospitable palette)
    static let pantryPrimary       = Color(hex: 0x2C5E43)  // Warm forest green
    static let pantryPrimaryLight  = Color(hex: 0xF4FAF6)
    static let pantryPrimaryContainer = Color(hex: 0xD3E7DD)
    static let pantryEmerald       = Color(hex: 0x3B855F)
    static let pantrySecondary     = Color(hex: 0x536A5F)  // Charcoal sage-gray
    static let pantrySecondaryContainer = Color(hex: 0xF0EBE3)
    static let pantryTertiary      = Color(hex: 0xD47A5C)  // Terracotta peach
    static let pantryTertiaryContainer = Color(hex: 0xF6E7DF)
    static let pantryBackground    = Color(hex: 0xFAF8F5)  // Oatmeal cream
    static let pantrySurface       = Color(hex: 0xFFFFFF)
    static let pantryTextDark      = Color(hex: 0x1E2622)  // Deep moss charcoal
    static let pantryTextMuted     = Color(hex: 0x5A6961)  // Mossy sage
    static let pantryBorder        = Color(hex: 0xE2E8F0)  // Card hairline used throughout the Kotlin UI
    static let pantryDivider       = Color(hex: 0xF1F5F9)
    static let pantryFieldFill     = Color(hex: 0xF8FAFC)
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
