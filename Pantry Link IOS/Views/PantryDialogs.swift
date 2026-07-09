//
//  PantryDialogs.swift
//  Pantry Link IOS
//
//  Ports of TermsOfServiceDialog, DiagnosticsDialog and WelcomeRewardsDialog
//  (PantryLinkWidgets.kt). Presented as sheets from the auth gate / root.
//

import SwiftUI

// MARK: - Terms of Service (Kotlin: TermsOfServiceDialog)

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, String)] = [
        ("1. Acceptance of Terms",
         "By accessing or using PantryLink Georgia (the \"Service\"), you agree to be bound by these Terms of Service. If you do not agree, do not use the Service."),
        ("2. The Service",
         "PantryLink Georgia connects individual and organizational donors with registered Food Bank Partners to coordinate the donation of shelf-stable food, hygiene items, baby supplies, school supplies and other approved categories."),
        ("3. Eligibility & Accounts",
         "You must provide accurate registration information and are responsible for maintaining the confidentiality of your account credentials and for all activity under your account."),
        ("4. Donor Responsibilities",
         "Donors are solely responsible for ensuring donated items are safe, unexpired, unopened where required, and accurately described. Food Bank Partners may reject items that are unsafe, damaged, opened, expired, or otherwise non-compliant."),
        ("5. Requests and Matching",
         "The Service enables Food Bank Partners to post requests for items such as shelf-stable food, hygiene items, baby supplies, school supplies, and other approved categories. Each request may include item description, category, quantity needed, drop-off location, deadline, pantry notes, and request status. Users may browse and claim listed requests. A request shall not be deemed completed, fulfilled, satisfied, or closed unless and until the relevant Food Bank Partner confirms receipt through the Service. PantryLink Georgia, Inc. reserves the right to standardize request categories, item descriptions, quantities, status labels, and workflows in order to improve accuracy, consistency, and usability."),
        ("6. No Warranty",
         "The Service is provided \"as is\" without warranties of any kind. PantryLink Georgia does not guarantee the accuracy of listings, the availability of items, or the outcome of any donation."),
        ("7. Limitation of Liability",
         "To the maximum extent permitted by law, PantryLink Georgia shall not be liable for any indirect, incidental, or consequential damages arising from use of the Service."),
        ("8. Privacy",
         "Your use of the Service is also governed by our Privacy Policy. We collect and process your information to operate and improve the Service.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.0)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.pantryPrimary)
                            Text(section.1)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.pantryTextDark)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Terms of Service")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .madeByCredit()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Privacy Policy (App Store requirement)

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, String)] = [
        ("Overview",
         "PantryLink Georgia (\"we\", \"the app\") connects donors with registered food banks. This policy explains what we collect, why, and your choices. We do not sell your data or use it for third-party advertising or tracking."),
        ("Information We Collect",
         "• Account info you provide: email address, name, and phone number.\n• Profile details: your city and ZIP code, and — for food banks — address, operating hours, and capacity.\n• Activity you create: requests, claims, and drop-off records.\nWe do not access your device's precise GPS location; the map centers on the ZIP code you enter."),
        ("How We Use It",
         "Your information is used solely to operate the service: authenticating your account, matching donors with nearby food-bank needs, coordinating drop-offs, and showing your activity. It is not used for advertising or sold to anyone."),
        ("Storage & Security",
         "Data is stored using Google Firebase (Authentication and Cloud Firestore) and on your device. Traffic is encrypted in transit. Access is governed by security rules. Passwords are handled by Firebase Authentication and are never stored by us in plain text."),
        ("Data Sharing",
         "Food banks you interact with can see the details of requests and claims relevant to a donation (e.g., item, quantity, and the donor identifier for a claim). We do not share your data with advertisers or data brokers."),
        ("Your Choices & Account Deletion",
         "You can edit your profile at any time. You can permanently delete your account and associated profile data from within the app: open the account menu (top-left ••• on any screen) and choose \"Delete Account.\" Deletion is immediate and irreversible."),
        ("Children's Privacy",
         "The service is not directed to children under 13, and we do not knowingly collect their information."),
        ("Contact",
         "Questions or requests about your data? Email us at \(PantrySupport.email) and we will respond promptly.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.0)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.pantryPrimary)
                            Text(section.1)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.pantryTextDark)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .madeByCredit()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

// MARK: - Diagnostics (Kotlin: DiagnosticsDialog)

struct DiagnosticsView: View {
    let report: [DiagnosticItem]
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(report) { item in
                HStack(alignment: .top, spacing: 12) {
                    icon(for: item.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 14, weight: .semibold))
                        Text(item.message).font(.system(size: 12)).foregroundStyle(Color.pantryTextMuted)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Connection Diagnostics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss(); dismiss() }
                }
            }
        }
    }

    @ViewBuilder private func icon(for status: DiagnosticStatus) -> some View {
        switch status {
        case .pending: ProgressView().controlSize(.small)
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.pantryPrimary)
        case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(Color.pantryTertiary)
        }
    }
}

// MARK: - Welcome rewards (Kotlin: WelcomeRewardsDialog)

struct WelcomeRewardsView: View {
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color.pantryTertiary)
                .padding(.top, 8)
            Text("Welcome to PantryLink Georgia!")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.pantryPrimary)
                .multilineTextAlignment(.center)
            Text("You're all set to start claiming community needs. Every accepted drop-off earns you recognition badges as you help feed Georgia neighborhoods.")
                .font(.system(size: 13))
                .foregroundStyle(Color.pantryTextDark)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                rewardRow("leaf.fill", "Seedling", "Your first accepted donation")
                rewardRow("tree.fill", "Grower", "5 accepted donations")
                rewardRow("crown.fill", "Community Champion", "20 accepted donations")
            }
            .padding(16)
            .background(Color.pantryPrimaryContainer.opacity(0.4), in: .rect(cornerRadius: 16))

            Button {
                onDismiss(); dismiss()
            } label: {
                Text("Start helping").font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.pantryPrimary)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
    }

    private func rewardRow(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.pantryPrimary).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted)
            }
            Spacer()
        }
    }
}
