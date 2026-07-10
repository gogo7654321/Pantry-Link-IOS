//
//  DonorAccountView.swift
//  Pantry Link IOS
//
//  Donor account management — the features Android bundles into "My Contacts & Claims",
//  here given their own sleek tab: profile header + edit, notification preferences, saved
//  drop-off locations, and account actions (sign out / delete). All wired to PantryLinkViewModel.
//

import SwiftUI
import MapKit

struct DonorAccountView: View {
    @Bindable var viewModel: PantryLinkViewModel

    // Editable profile fields (populated from the current profile on appear)
    @State private var fullName = ""
    @State private var phone = ""
    @State private var city = ""
    @State private var zip = ""
    @State private var canServeType = "All Categories"
    @State private var canServeQty = "Trunk Load"
    @State private var frequency = "Weekly"
    @State private var loaded = false
    @State private var savedCount = 0

    // Saved locations add form
    @State private var isAdding = false
    @State private var locName = ""
    @State private var locAddr = ""
    @State private var locZip = ""
    @State private var locNotes = ""
    @State private var locLat: Double? = nil
    @State private var locLng: Double? = nil
    @State private var addr = AddressSearchModel()

    @State private var showDeleteConfirm = false

    private var acceptedCount: Int { viewModel.claims.filter { $0.claimStatus == "Accepted" }.count }
    private var selectedCategories: Set<String> {
        Set(canServeType.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
    private var initials: String {
        let n = fullName.trimmingCharacters(in: .whitespaces)
        let base = n.isEmpty ? String(viewModel.currentUserEmail.prefix(2)) : n
        return String(base.prefix(2)).uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileHeader
                editProfileCard
                notificationsCard
                savedLocationsCard
                accountActions
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear(perform: load)
        .confirmationDialog("Delete your account permanently?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task {
                    let (ok, msg) = await viewModel.deleteUserAccount()
                    if !ok { viewModel.showToast(msg) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account, profile, and claims. This cannot be undone.")
        }
    }

    // MARK: Profile header (avatar + name + badge + a subtle brand logo)

    private var profileHeader: some View {
        let badge = getBadgeInfo(acceptedCount)
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.pantryPrimaryContainer).frame(width: 60, height: 60)
                Text(initials).font(.system(size: 20, weight: .black)).foregroundStyle(Color.pantryPrimary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(fullName.isEmpty ? "PantryLink Member" : fullName)
                        .font(.system(size: 18, weight: .heavy)).foregroundStyle(Color.pantryTextDark)
                    Image(systemName: badge.symbol).font(.system(size: 14)).foregroundStyle(badge.text)
                }
                Text(viewModel.currentUserEmail).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(badge.title).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(badge.text)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badge.container, in: .capsule)
            }
            Spacer()
            PantryLogo(size: 46)
        }
        .padding(16)
        .background(Color.pantrySurface, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.pantryBorder.opacity(0.7), lineWidth: 1))
    }

    // MARK: Edit profile

    private var editProfileCard: some View {
        card(title: "Edit Profile", icon: "person.text.rectangle") {
            field("Full Name", text: $fullName)
            field("Contact Phone", text: $phone).keyboardType(.phonePad)
            HStack(spacing: 10) {
                field("Base City (GA)", text: $city)
                field("ZIP Code", text: $zip).keyboardType(.numberPad)
            }
            label("Food categories you can serve")
            ChipGrid(items: PantryConstants.donorFoodTypesWithAll, columns: 3,
                     isSelected: { categoryIsSelected($0) }, onTap: { toggleCategory($0) })
            label("Typical donation capacity")
            ChipGrid(items: PantryConstants.donorCapacities, columns: 2,
                     isSelected: { $0 == canServeQty }, onTap: { canServeQty = $0 })
            label("How often can you donate?")
            ChipGrid(items: PantryConstants.frequencies, columns: 2,
                     isSelected: { $0 == frequency }, onTap: { frequency = $0 })

            Button { save() } label: {
                Text("Save Profile").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).tint(Color.pantryPrimary).padding(.top, 4)
        }
    }

    // MARK: Notifications

    private var notificationsCard: some View {
        card(title: "Notification Preferences", icon: "bell.badge") {
            toggleRow("Push Alerts", "Urgent local pantry needs", "bell.fill", enabled: true,
                      isOn: viewModel.pushNotificationsEnabled) { viewModel.togglePushNotifications() }
            Divider().overlay(Color.pantryDivider)
            toggleRow("Email Confirmations (Coming Soon)", "Automated tax logs & receipts", "envelope.fill",
                      enabled: false, isOn: viewModel.emailNotificationsEnabled) {}
            Divider().overlay(Color.pantryDivider)
            toggleRow("SMS Direct Alerts (Coming Soon)", "Real-time dispatch coordination", "message.fill",
                      enabled: false, isOn: viewModel.smsNotificationsEnabled) {}
        }
    }

    // MARK: Saved locations

    private var savedLocationsCard: some View {
        card(title: "Saved Drop-off Coordinates", icon: "mappin.and.ellipse", trailing: {
            Button(isAdding ? "Cancel" : "+ Add") {
                withAnimation { isAdding.toggle() }
                if !isAdding { resetAddForm() }
            }
            .font(.system(size: 13, weight: .bold)).tint(Color.pantryPrimary)
        }) {
            if viewModel.savedLocations.isEmpty && !isAdding {
                Text("No saved locations yet.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(viewModel.savedLocations) { loc in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "star.circle.fill").foregroundStyle(Color.pantryTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(loc.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                            Text(loc.zipCode.isEmpty ? loc.address : "\(loc.address) (\(loc.zipCode))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { viewModel.removeSavedLocation(id: loc.id) } label: {
                            Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(.red)
                        }
                    }
                    // Editable notes for this saved location (gate code, hours, contact…).
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted).padding(.top, 2)
                        TextField("Add a note (gate code, hours, contact…)",
                                  text: Binding(get: { loc.notes },
                                                set: { viewModel.updateSavedLocationNotes(id: loc.id, notes: $0) }),
                                  axis: .vertical)
                            .font(.system(size: 11.5)).foregroundStyle(Color.pantryTextDark)
                    }
                    .padding(8).background(Color.pantryFieldFill, in: .rect(cornerRadius: 8))
                }
                .padding(.vertical, 4)
            }
            if isAdding { addForm }
        }
    }

    /// Add form with native MapKit address autocomplete (exact coordinates, no formatting slip-ups).
    private var addForm: some View {
        VStack(spacing: 8) {
            field("Label (e.g., Home, Office)", text: $locName)

            field("Search address…", text: Binding(get: { addr.query }, set: { addr.query = $0 }))
                .autocorrectionDisabled()

            if !addr.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(addr.suggestions.prefix(5).enumerated()), id: \.offset) { _, s in
                        Button { Task { await choose(s) } } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.pantryTextDark)
                                if !s.subtitle.isEmpty {
                                    Text(s.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color.pantrySurface, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.pantryBorder, lineWidth: 1))
            }

            if !locAddr.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.pantryPrimary).font(.system(size: 12))
                    Text(locZip.isEmpty ? locAddr : "\(locAddr) (\(locZip))")
                        .font(.system(size: 11)).foregroundStyle(Color.pantryTextDark)
                    Spacer()
                }
            }

            field("Notes (optional)", text: $locNotes)

            Button {
                viewModel.addSavedLocation(name: locName, address: locAddr, zipCode: locZip,
                                           notes: locNotes, latitude: locLat, longitude: locLng)
                resetAddForm(); withAnimation { isAdding = false }
            } label: {
                Text("Save Location").font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent).tint(Color.pantryPrimary)
            .disabled(locName.isBlank || locAddr.isBlank)
        }
        .padding(12).background(Color.pantryFieldFill, in: .rect(cornerRadius: 12))
    }

    /// Resolve a chosen autocomplete suggestion to exact coordinates + clean address parts.
    private func choose(_ s: MKLocalSearchCompletion) async {
        guard let r = await addr.resolve(s) else {
            viewModel.showToast("Couldn't resolve that address — try another.")
            return
        }
        locAddr = r.street
        locZip = r.zip
        locLat = r.latitude
        locLng = r.longitude
        if locName.isBlank { locName = s.title }   // sensible default label
        addr.clear()                               // hide the suggestion list
    }

    private func resetAddForm() {
        locName = ""; locAddr = ""; locZip = ""; locNotes = ""
        locLat = nil; locLng = nil
        addr.clear()
    }

    // MARK: Account actions

    private var accountActions: some View {
        VStack(spacing: 10) {
            Button { viewModel.signOutUser() } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain).foregroundStyle(Color.pantryPrimary)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pantryPrimary.opacity(0.5), lineWidth: 1))
            .accessibilityIdentifier("sign_out")

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete Account", systemImage: "trash")
                    .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain).foregroundStyle(.red)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.5), lineWidth: 1))
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    private func load() {
        guard !loaded, let p = viewModel.currentUserProfile else { return }
        fullName = p.name; phone = p.phone; city = p.donorCity; zip = p.donorZip
        if !p.donorCanServeType.isEmpty { canServeType = p.donorCanServeType }
        if !p.donorCanServeQty.isEmpty { canServeQty = p.donorCanServeQty }
        if !p.donorFrequency.isEmpty { frequency = p.donorFrequency }
        loaded = true
    }

    private func save() {
        Task {
            _ = await viewModel.updateProfile(
                name: fullName, phone: phone, donorZip: zip, donorCity: city,
                donorCanServeType: canServeType, donorCanServeQty: canServeQty, donorFrequency: frequency)
            savedCount += 1
        }
    }

    private func categoryIsSelected(_ item: String) -> Bool {
        item == "All Categories" ? canServeType == "All Categories" : selectedCategories.contains(item)
    }
    private func toggleCategory(_ item: String) {
        if item == "All Categories" { canServeType = "All Categories"; return }
        var set = Set(canServeType.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "All Categories" })
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        canServeType = set.isEmpty ? "All Categories" : set.sorted().joined(separator: ", ")
    }

    // MARK: Small builders

    @ViewBuilder
    private func card<Content: View, Trailing: View>(
        title: String, icon: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pantrySurface, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.pantryBorder.opacity(0.7), lineWidth: 1))
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14)).padding(12)
            .background(Color.pantryFieldFill, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.pantryBorder, lineWidth: 1))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.pantrySecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ icon: String,
                           enabled: Bool, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(enabled ? Color.pantryPrimary : Color.pantryTextMuted).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(enabled ? Color.pantryTextDark : Color.pantryTextMuted)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .labelsHidden().tint(Color.pantryPrimary).disabled(!enabled)
        }
        .padding(.vertical, 4)
    }
}

// String.isBlank is fileprivate in other files; add a local copy for this view.
private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
