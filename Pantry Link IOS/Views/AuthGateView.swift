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
    @State private var signUpStep = 1        // 1 = account basics, 2 = role-specific details
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
            Text(cardTitle)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Color.pantryPrimary)
                .multilineTextAlignment(.center)
            Text(cardSubtitle)
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

            if !isSignUp {
                // ── Sign in ──
                credentialFields
                if loading { ProgressView().padding(.vertical, 6) } else { actionButtons }
            } else if signUpStep == 1 {
                // ── Sign up · Step 1: account basics only (don't bombard) ──
                stepBadge("Step 1 of 2 · Account basics")
                basicsFields
                credentialFields
                termsRow
                if loading { ProgressView().padding(.vertical, 6) } else { step1Buttons }
            } else {
                // ── Sign up · Step 2: role-specific details ──
                stepBadge(role == PantryRole.donor.rawValue
                          ? "Step 2 of 2 · Donation details"
                          : "Step 2 of 2 · Pantry details")
                if role == PantryRole.donor.rawValue { donorProfileFields } else { foodBankProfileFields }
                if loading { ProgressView().padding(.vertical, 6) } else { step2Buttons }
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
        // Clean rounded logo badge (no hard white square, no circular crop of the wordmark).
        PantryLogo(size: 132)
            .frame(maxWidth: .infinity)   // horizontal centering within the card
            .padding(.top, 8)
    }

    // MARK: - Sign-up fields

    /// Email + password, shared by sign-in and sign-up step 1.
    @ViewBuilder private var credentialFields: some View {
        PantryField(title: "Email Address", systemImage: "envelope", text: $email, contentType: .username)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
        // Sign-up: `.newPassword` so iOS offers a generated strong password + prompts to save it to
        // iCloud Keychain. Sign-in: `.password` so iOS AutoFills an existing saved credential.
        PantryField(title: "Password", systemImage: "lock", text: $password, secure: true,
                    contentType: isSignUp ? .newPassword : .password)
    }

    /// Step 1 — the basics: role, name, phone (the specifics come on step 2).
    @ViewBuilder private var basicsFields: some View {
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
    }

    @ViewBuilder private var donorProfileFields: some View {
        sectionLabel("Donor Profile & Logistics", color: .pantryPrimary, heavy: true)
        AddressAutocompleteField(title: "Base City or Address (GA)", systemImage: "location", text: $donorCity) { r in
            if !r.city.isEmpty { donorCity = r.city }
            if !r.zip.isEmpty { donorZip = r.zip }
        }
        PantryField(title: "ZIP Code", systemImage: "location", text: $donorZip)
            .keyboardType(.numberPad)
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
        AddressAutocompleteField(title: "Street Address", text: $fbAddress) { r in
            if !r.city.isEmpty { fbCity = r.city }
            if !r.zip.isEmpty { fbZip = r.zip }
        }
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

    /// Sign-in screen buttons.
    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: submit) {
                Text("Sign In")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.pantryPrimary)
            .accessibilityIdentifier("auth_submit")

            Button {
                isSignUp = true; signUpStep = 1; errorMessage = nil
            } label: {
                Text("Don't have an account yet? Create one")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.pantryPrimary)
            }
            legalRow
        }
    }

    /// Step 1 (basics) buttons: advance to details, or switch to sign-in.
    private var step1Buttons: some View {
        VStack(spacing: 8) {
            Button(action: goToDetails) {
                Label("Next", systemImage: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.pantryPrimary)
            .accessibilityIdentifier("auth_next")

            Button {
                isSignUp = false; signUpStep = 1; errorMessage = nil
            } label: {
                Text("Already have an account? Sign In")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.pantryPrimary)
            }
            legalRow
        }
    }

    /// Step 2 (details) buttons: register, or go back to the basics.
    private var step2Buttons: some View {
        VStack(spacing: 8) {
            Button(action: submit) {
                Text("Register now")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.pantryPrimary)
            .accessibilityIdentifier("auth_submit")

            Button {
                withAnimation { signUpStep = 1 }; errorMessage = nil
            } label: {
                Label("Back to basics", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.pantryPrimary)
            }
        }
    }

    /// Legal + support links, accessible before sign-in (also required-ish for App Review).
    private var legalRow: some View {
        VStack(spacing: 8) {
            Text("By using this service, you agree to our Terms of Service.")
                .font(.system(size: 10)).foregroundStyle(Color.pantryTextMuted)
                .multilineTextAlignment(.center)
            Divider().overlay(Color.pantryDivider).padding(.vertical, 4)
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

    private var cardTitle: String {
        if !isSignUp { return "Community Portal Sign In" }
        return signUpStep == 1 ? "Create Partner Account" : "Almost there!"
    }

    private var cardSubtitle: String {
        if !isSignUp { return "Access your Georgia PantryLink dashboard and claims" }
        return signUpStep == 1
            ? "Start with the basics — you'll add a few details next"
            : "Just a few details so we can match you with the right needs"
    }

    private func stepBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(Color.pantryPrimary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.pantryPrimaryContainer, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Validate the basics before advancing to the details step.
    private func goToDetails() {
        errorMessage = nil
        let nameOk = role == PantryRole.donor.rawValue
            ? !(donorFirstName.isBlank && donorLastName.isBlank)
            : !name.isBlank
        if !nameOk {
            errorMessage = role == PantryRole.donor.rawValue
                ? "Please enter your first and last name."
                : "Please enter your food bank name."
            return
        }
        if !PantryLinkViewModel.isValidEmail(email) { errorMessage = "Please enter a valid email address."; return }
        if password.count < 6 { errorMessage = "Password must be at least 6 characters."; return }
        if !agreedToTerms { errorMessage = "You must agree to the Terms of Service to register."; return }
        withAnimation { signUpStep = 2 }
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

    // For secure fields: whether the password is currently revealed (tap the eye to toggle).
    @State private var reveal = false

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 14)).foregroundStyle(Color.pantryTextMuted)
            }
            Group {
                if secure && !reveal {
                    SecureField(title, text: $text).textContentType(contentType)
                } else {
                    TextField(title, text: $text).textContentType(contentType)
                        // Revealed passwords shouldn't be autocorrected or auto-capitalized.
                        .autocorrectionDisabled(secure)
                        .textInputAutocapitalization(secure ? .never : .sentences)
                }
            }
            .font(.system(size: 14))
            // Show/hide eye — only on secure fields.
            if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14)).foregroundStyle(Color.pantryTextMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reveal ? "Hide password" : "Show password")
            }
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
