//
//  AuthGateView.swift
//  Pantry Link IOS
//
//  Port of PantryLinkAuthGateScreen (PantryLinkWidgets.kt:4212).
//  Sign in / sign up for Donor & Food Bank, all role-specific fields, Terms agreement,
//  validation and diagnostics — wired to PantryLinkViewModel. Styled with real iOS 26
//  Liquid Glass (`.glassEffect`, `.buttonStyle(.glassProminent)`).
//
//  Note: the Android screen also does live Google Places address autocomplete. Places
//  isn't linked in this build (offline slice), so the address is a plain field here; the
//  autocomplete drops in with the networking slice via the existing service seam.
//

import SwiftUI

struct AuthGateView: View {
    @Bindable var viewModel: PantryLinkViewModel

    // Mode
    @State private var isSignUp = false
    @State private var agreedToTerms = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showSupport = false

    // Shared credentials
    @State private var email = ""
    @State private var password = ""
    @State private var phone = ""
    @State private var role = PantryRole.donor.rawValue

    // Donor fields
    @State private var donorFirstName = ""
    @State private var donorLastName = ""
    @State private var donorCity = ""
    @State private var donorZip = ""
    @State private var donorCanServeType = "All Categories"
    @State private var donorCanServeQty = "Trunk Load"
    @State private var donorFrequency = "Weekly"

    // Food Bank fields
    @State private var name = ""
    @State private var fbAddress = ""
    @State private var fbCity = ""
    @State private var fbZip = ""
    @State private var fbSize = ""
    @State private var opDaysSelection = "Mon-Fri"
    @State private var opHoursSelection = "9 AM - 5 PM"
    @State private var opCustomHours = ""
    @State private var opHoursNotes = ""
    @State private var fbColdStorage = false

    private var donorSelectedCategories: Set<String> {
        Set(donorCanServeType.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    var body: some View {
        ZStack {
            PantryBackground()
            ScrollView {
                card
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
        }
        .madeByCredit()
        .sheet(isPresented: $showTerms) { TermsOfServiceView() }
        .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
        .supportDialog(isPresented: $showSupport, viewModel: viewModel)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 14) {
            logo
            Text(isSignUp ? "Create Partner Account" : "Community Portal Sign In")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Color.pantryPrimary)
                .multilineTextAlignment(.center)
            Text(isSignUp
                 ? "Register to coordinate and track stock across Georgia"
                 : "Access your Georgia PantryLink dashboard and claims")
                .font(.system(size: 12))
                .foregroundStyle(Color.pantryTextMuted)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 8))
                    .multilineTextAlignment(.center)
            }

            if isSignUp { signUpFields }

            PantryField(title: "Email Address", systemImage: "envelope", text: $email, contentType: .emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            // `.password` (not `.newPassword`) avoids the strong-password overlay intercepting input.
            PantryField(title: "Password", systemImage: "lock", text: $password, secure: true, contentType: .password)

            if isSignUp { termsRow }

            if loading {
                ProgressView().padding(.vertical, 6)
            } else {
                actionButtons
            }
        }
        .padding(24)
        // Solid baseline: form inputs must NOT sit on raw glass (Liquid Glass rule).
        // Glass is reserved for the controls that float above (role selector + submit button).
        .background(Color.pantrySurface, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.pantryBorder, lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }

    private var logo: some View {
        // Show the FULL logo (illustration + wordmark). No circular clip — that cropped the
        // "PantryLink" wordmark. scaledToFit keeps the whole square artwork intact.
        Image("app_logo")
            .resizable()
            .scaledToFit()
            .frame(height: 150)
            .frame(maxWidth: .infinity)   // horizontal centering within the card
            .padding(.top, 8)
    }

    // MARK: - Sign-up fields

    @ViewBuilder private var signUpFields: some View {
        // Role selector
        sectionLabel("I want to join as a:", color: .pantrySecondary)
        HStack(spacing: 10) {
            roleButton("Donor", systemImage: "hands.sparkles")
            roleButton("Food Bank", systemImage: "storefront")
        }
        Divider().overlay(Color.pantryDivider)

        if role == PantryRole.donor.rawValue {
            HStack(spacing: 10) {
                PantryField(title: "First Name", systemImage: "person", text: $donorFirstName)
                PantryField(title: "Last Name", systemImage: "person", text: $donorLastName)
            }
        } else {
            PantryField(title: "Food Bank / Agency Name", systemImage: "storefront", text: $name)
        }

        PantryField(title: "Contact Phone", systemImage: "phone", text: $phone)
            .keyboardType(.phonePad)

        if role == PantryRole.donor.rawValue { donorProfileFields } else { foodBankProfileFields }
    }

    @ViewBuilder private var donorProfileFields: some View {
        sectionLabel("Donor Profile & Logistics", color: .pantryPrimary, heavy: true)
        HStack(spacing: 10) {
            PantryField(title: "Base City (GA)", systemImage: nil, text: $donorCity)
            PantryField(title: "ZIP Code", systemImage: "location", text: $donorZip)
                .keyboardType(.numberPad)
        }
        sectionLabel("What category of food can you serve / donate?", color: .pantryPrimary)
        Text("Select all food types you are equipped to handle. Choose 'All Categories' to reset.")
            .font(.system(size: 10)).foregroundStyle(Color.pantryTextMuted)
            .frame(maxWidth: .infinity, alignment: .leading)

        ChipGrid(items: PantryConstants.donorFoodTypesWithAll, columns: 3,
                 isSelected: { donorCategoryIsSelected($0) },
                 onTap: { toggleDonorCategory($0) })

        sectionLabel("Typical donation capacity", color: .pantryPrimary)
        ChipGrid(items: PantryConstants.donorCapacities, columns: 2,
                 isSelected: { $0 == donorCanServeQty }, onTap: { donorCanServeQty = $0 })

        sectionLabel("How often can you donate?", color: .pantryPrimary)
        ChipGrid(items: PantryConstants.frequencies, columns: 2,
                 isSelected: { $0 == donorFrequency }, onTap: { donorFrequency = $0 })
    }

    @ViewBuilder private var foodBankProfileFields: some View {
        sectionLabel("Food Bank Location & Operations", color: .pantryPrimary, heavy: true)
        PantryField(title: "Street Address", systemImage: "mappin.and.ellipse", text: $fbAddress)
        HStack(spacing: 10) {
            PantryField(title: "City (GA)", systemImage: nil, text: $fbCity)
            PantryField(title: "ZIP Code", systemImage: "location", text: $fbZip)
                .keyboardType(.numberPad)
        }
        sectionLabel("Facility size", color: .pantryPrimary)
        ChipGrid(items: PantryConstants.foodBankSizes, columns: 1,
                 isSelected: { $0 == fbSize }, onTap: { fbSize = $0 })

        sectionLabel("Operating days", color: .pantryPrimary)
        ChipGrid(items: PantryConstants.operatingDays, columns: 3,
                 isSelected: { $0 == opDaysSelection }, onTap: { opDaysSelection = $0 })

        sectionLabel("Operating hours", color: .pantryPrimary)
        ChipGrid(items: PantryConstants.operatingHoursPresets, columns: 2,
                 isSelected: { $0 == opHoursSelection }, onTap: { opHoursSelection = $0 })
        if opHoursSelection == "Custom Hours" {
            PantryField(title: "E.g., 7:30 AM - 11 AM, 2 PM - 6 PM", systemImage: "clock", text: $opCustomHours)
        }
        PantryField(title: "Holiday Exceptions & General Notes", systemImage: "note.text", text: $opHoursNotes)

        // Cold storage toggle
        HStack {
            Image(systemName: "snowflake").foregroundStyle(Color.pantryPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Refrigerated Cold Storage Available")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                Text("Check this if you can accept fresh/frozen items")
                    .font(.system(size: 10)).foregroundStyle(Color.pantryTextMuted)
            }
            Spacer()
            Toggle("", isOn: $fbColdStorage).labelsHidden().tint(Color.pantryPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.pantryPrimary.opacity(0.03), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.pantryBorder, lineWidth: 1))
        Divider().overlay(Color.pantryDivider)
    }

    // MARK: - Terms row

    private var termsRow: some View {
        HStack(spacing: 8) {
            Button { agreedToTerms.toggle() } label: {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                    .foregroundStyle(agreedToTerms ? Color.pantryPrimary : Color.pantryTextMuted)
            }
            .accessibilityIdentifier("auth_terms")
            Text("I agree to the ").font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted)
            + Text("Terms of Service").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.pantryPrimary)
            Spacer()
        }
        .onTapGesture { showTerms = true }
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: submit) {
                Text(isSignUp ? "Register now" : "Sign In")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.pantryPrimary)
            .accessibilityIdentifier("auth_submit")

            Button {
                isSignUp.toggle()
                errorMessage = nil
            } label: {
                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account yet? Create one")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.pantryPrimary)
            }

            Text("By using this service, you agree to our Terms of Service.")
                .font(.system(size: 10)).foregroundStyle(Color.pantryTextMuted)
                .multilineTextAlignment(.center)

            Divider().overlay(Color.pantryDivider).padding(.vertical, 4)

            // Legal + support, accessible before sign-in.
            HStack(spacing: 14) {
                Button("Terms") { showTerms = true }
                Text("·").foregroundStyle(Color.pantryTextMuted)
                Button("Privacy") { showPrivacy = true }
                Text("·").foregroundStyle(Color.pantryTextMuted)
                Button("Contact Support") { showSupport = true }
            }
            .font(.system(size: 12, weight: .semibold))
            .tint(Color.pantryPrimary)
            .foregroundStyle(Color.pantryPrimary)
        }
    }

    // MARK: - Actions

    private func submit() {
        if isSignUp && !agreedToTerms {
            errorMessage = "You must agree to the Terms of Service to register."
            return
        }
        loading = true
        errorMessage = nil
        Task {
            let result: (Bool, String)
            if isSignUp {
                result = await viewModel.signUp(
                    email: email, password: password, role: role,
                    name: role == PantryRole.donor.rawValue
                        ? "\(donorFirstName) \(donorLastName)".trimmingCharacters(in: .whitespaces)
                        : name,
                    phone: phone,
                    fbAddress: fbAddress, fbCity: fbCity, fbZip: fbZip, fbSize: fbSize,
                    fbHours: calculatedFbHours, fbColdStorage: fbColdStorage,
                    donorZip: donorZip, donorCity: donorCity,
                    donorCanServeType: donorCanServeType, donorCanServeQty: donorCanServeQty,
                    donorFrequency: donorFrequency)
            } else {
                result = await viewModel.signIn(email: email, password: password)
            }
            loading = false
            if !result.0 { errorMessage = result.1 }
        }
    }

    /// Kotlin: buildString { … } assembling the human-readable hours string on submit.
    private var calculatedFbHours: String {
        guard role == PantryRole.foodBank.rawValue else { return "" }
        var s = opDaysSelection + " "
        if opHoursSelection == "Custom Hours" {
            s += opCustomHours.isBlank ? "Flexible Hours" : opCustomHours
        } else {
            s += opHoursSelection
        }
        if !opHoursNotes.isBlank { s += " (Notes: \(opHoursNotes))" }
        return s
    }

    private func donorCategoryIsSelected(_ item: String) -> Bool {
        item == "All Categories" ? donorCanServeType == "All Categories" : donorSelectedCategories.contains(item)
    }

    /// Kotlin donor category toggle logic (verbatim).
    private func toggleDonorCategory(_ item: String) {
        if item == "All Categories" {
            donorCanServeType = "All Categories"
            return
        }
        var set = Set(donorCanServeType.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "All Categories" })
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        donorCanServeType = set.isEmpty ? "All Categories" : set.sorted().joined(separator: ", ")
    }

    // MARK: - Small builders

    private func sectionLabel(_ text: String, color: Color, heavy: Bool = false) -> some View {
        Text(text)
            .font(.system(size: heavy ? 12.5 : 11, weight: heavy ? .heavy : .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func roleButton(_ r: String, systemImage: String) -> some View {
        let active = role == r
        return Button { role = r } label: {
            Label(r, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.pantryPrimary : Color.pantryTextMuted)
        .pantryGlassChip(tint: .pantryPrimary, selected: active)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(active ? Color.pantryPrimary : Color.pantryBorder, lineWidth: 1.2))
    }
}

// MARK: - Reusable field

struct PantryField: View {
    let title: String
    let systemImage: String?
    @Binding var text: String
    var secure: Bool = false
    var contentType: UITextContentType? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 14)).foregroundStyle(Color.pantryTextMuted)
            }
            Group {
                if secure {
                    SecureField(title, text: $text).textContentType(contentType)
                } else {
                    TextField(title, text: $text).textContentType(contentType)
                }
            }
            .font(.system(size: 14))
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(Color.pantryFieldFill, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pantryBorder, lineWidth: 1))
    }
}

// MARK: - Chip grid (selectable options)

struct ChipGrid: View {
    let items: [String]
    let columns: Int
    let isSelected: (String) -> Bool
    let onTap: (String) -> Void

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let selected = isSelected(item)
                Button { onTap(item) } label: {
                    HStack(spacing: 4) {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        }
                        Text(item).font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10).padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? Color.pantryPrimary : Color.pantryTextMuted)
                .background(selected ? Color.pantryPrimaryContainer : Color.pantryFieldFill, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.pantryPrimary : Color.pantryBorder, lineWidth: 1))
            }
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
