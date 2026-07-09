//
//  GlassKit.swift
//  Pantry Link IOS
//
//  Liquid Glass building blocks that follow the architecture rules:
//   • glass lives on control / nav / notification layers only (never under walls of text)
//   • real `.glassEffect` (no `.ultraThinMaterial`), `.interactive()` for tactility
//   • `GlassEffectContainer` + `.glassEffectID` for shape-morphing selection
//   • Reduce Transparency fallback to a solid surface everywhere
//

import SwiftUI
import UIKit

// MARK: - Support contact

enum PantrySupport {
    static let email = "pantrylinkgeorgia@gmail.com"
    static var mailtoURL: URL {
        URL(string: "mailto:\(email)?subject=PantryLink%20Georgia%20Support")
            ?? URL(string: "mailto:\(email)")!
    }
}

/// Support dialog that works for EVERYONE — including users with no Mail app configured.
/// Offers "Copy Email Address" (always works) alongside "Open in Mail".
private struct SupportDialog: ViewModifier {
    @Binding var isPresented: Bool
    let viewModel: PantryLinkViewModel
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.confirmationDialog("Contact Support", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Copy Email Address") {
                UIPasteboard.general.string = PantrySupport.email
                viewModel.showToast("Support email copied: \(PantrySupport.email)")
            }
            Button("Open in Mail") { openURL(PantrySupport.mailtoURL) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reach us at \(PantrySupport.email)")
        }
    }
}

extension View {
    func supportDialog(isPresented: Binding<Bool>, viewModel: PantryLinkViewModel) -> some View {
        modifier(SupportDialog(isPresented: isPresented, viewModel: viewModel))
    }
}

// MARK: - Workspace chrome (native large-title nav + account menu + Sign Out + gradient)

private struct WorkspaceChrome: ViewModifier {
    let title: String
    let large: Bool
    let viewModel: PantryLinkViewModel

    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showDeleteConfirm = false
    @State private var showSupport = false

    func body(content: Content) -> some View {
        content
            .background(PantryBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showSupport = true } label: {
                            Label("Contact Support", systemImage: "envelope")
                        }
                        Button { showPrivacy = true } label: { Label("Privacy Policy", systemImage: "hand.raised") }
                        Button { showTerms = true } label: { Label("Terms of Service", systemImage: "doc.text") }
                        Divider()
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete Account", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("Account menu")
                    }
                    .tint(Color.pantryPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { viewModel.signOutUser() }
                        .font(.system(size: 15, weight: .semibold))
                        .tint(Color.pantryPrimary)
                        .accessibilityIdentifier("sign_out")
                }
            }
            .sheet(isPresented: $showTerms) { TermsOfServiceView() }
            .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
            .confirmationDialog("Delete your account permanently?",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        let (ok, message) = await viewModel.deleteUserAccount()
                        if !ok { viewModel.showToast(message) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes your account, profile, and data. This cannot be undone. For help, contact \(PantrySupport.email).")
            }
            .supportDialog(isPresented: $showSupport, viewModel: viewModel)
    }
}

extension View {
    /// Wraps a tab's root in the standard native chrome: large title, a Sign Out toolbar button,
    /// and the app's gradient. The bottom tab bar itself is the system's Liquid Glass TabView.
    func workspaceChrome(_ title: String, large: Bool = true, viewModel: PantryLinkViewModel) -> some View {
        modifier(WorkspaceChrome(title: title, large: large, viewModel: viewModel))
    }
}

// MARK: - Reduce-Transparency-aware glass surface (for floating panels / notifications)

private struct PantryGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let tint: Color?
    let interactive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color.pantrySurface, in: shape)
                .overlay(shape.strokeBorder(Color.pantryBorder, lineWidth: 1))
        } else {
            content.glassEffect(resolvedGlass, in: shape)
        }
    }

    // Computed outside the @ViewBuilder body so the imperative build is legal.
    private var resolvedGlass: Glass {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// Floating glass panel with an automatic solid fallback under Reduce Transparency.
    func pantryGlass(tint: Color? = nil, interactive: Bool = false, cornerRadius: CGFloat = 20) -> some View {
        modifier(PantryGlassModifier(tint: tint, interactive: interactive, cornerRadius: cornerRadius))
    }
}

// MARK: - Morphing glass tab bar (a floating control cluster)

struct GlassTabBar: View {
    struct Item { let title: String; let icon: String }
    let items: [Item]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(items.indices, id: \.self) { i in
                        tabButton(i)
                    }
                }
                .padding(6)
            }
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }

    // Active tab = prominent glass — the system keeps its label crisp & high-contrast (white on
    // the green tint). Inactive = subtle glass with dark label. Native styles handle press
    // states and Reduce Transparency automatically. glassEffectID drives the morph.
    @ViewBuilder
    private func tabButton(_ i: Int) -> some View {
        let active = selection == i
        if active {
            Button { select(i) } label: { label(i) }
                .buttonStyle(.glassProminent)
                .tint(Color.pantryPrimary)
                .glassEffectID("selectedTab", in: ns)
        } else {
            Button { select(i) } label: { label(i).foregroundStyle(Color.pantryTextDark) }
                .buttonStyle(.glass)
                .glassEffectID("tab_\(i)", in: ns)
        }
    }

    private func label(_ i: Int) -> some View {
        Label(items[i].title, systemImage: items[i].icon)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 16)
            .frame(height: 40)
    }

    private func select(_ i: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { selection = i }
    }
}
