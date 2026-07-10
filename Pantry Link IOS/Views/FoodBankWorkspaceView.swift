//
//  FoodBankWorkspaceView.swift
//  Pantry Link IOS
//
//  Port of FoodBankWorkspace + FBActiveNeedsTab / FBPostRequestTab / FBVerifyDropsTab /
//  FBAuditLogsTab / FBProfileTab (PantryLinkWidgets.kt). Posting a request writes to the
//  shared "requests" Firestore collection (same schema as Android) so it appears for donors
//  on both apps. Verify approves/rejects drop-offs; all logic runs through PantryLinkViewModel.
//

import SwiftUI

struct FoodBankWorkspaceView: View {
    @Bindable var viewModel: PantryLinkViewModel

    var body: some View {
        TabView {
            Tab("Inventory", systemImage: "shippingbox.fill") {
                NavigationStack { FBActiveNeedsView(viewModel: viewModel).workspaceChrome("Inventory Needs", viewModel: viewModel) }
            }
            Tab("Post", systemImage: "plus.app.fill") {
                NavigationStack { FBPostRequestView(viewModel: viewModel).workspaceChrome("Post Request", viewModel: viewModel) }
            }
            Tab("Verify", systemImage: "checkmark.seal.fill") {
                NavigationStack { FBVerifyDropsView(viewModel: viewModel).workspaceChrome("Verify Deliveries", viewModel: viewModel) }
            }
            Tab("Audit", systemImage: "clock.arrow.circlepath") {
                NavigationStack { FBAuditView(viewModel: viewModel).workspaceChrome("Audit Trail", viewModel: viewModel) }
            }
            Tab("Profile", systemImage: "person.crop.circle.fill") {
                NavigationStack { FBProfileView(viewModel: viewModel).workspaceChrome("My Profile", viewModel: viewModel) }
            }
        }
        .tint(Color.pantryPrimary)
        .task { await viewModel.refreshAll() }
    }
}

// MARK: - Inventory Needs (FBActiveNeedsTab)

struct FBActiveNeedsView: View {
    @Bindable var viewModel: PantryLinkViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("📋 Partner Request Management",
                       "Shared backend source-of-truth. Closes requests when requirements are confirmed.")
                if viewModel.requests.isEmpty {
                    EmptyStateCard(icon: "shippingbox", title: "No needs posted yet.",
                                   subtitle: "Tap 'Post Requests' to list items donors can fulfill.")
                } else {
                    ForEach(viewModel.requests) { req in needCard(req) }
                }
            }
            .padding(16)
        }
    }

    private func needCard(_ req: RequestDTO) -> some View {
        let closed = req.status == "Closed"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(req.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                    Text("Category: \(req.category)").font(.system(size: 12)).foregroundStyle(Color.pantryPrimary)
                }
                Spacer()
                Text(req.status).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(closed ? .gray : Color.pantryPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((closed ? Color.gray.opacity(0.15) : Color.pantryPrimaryContainer), in: .rect(cornerRadius: 6))
            }
            Text(req.itemDescription).font(.system(size: 13)).foregroundStyle(Color.pantryTextDark)
            HStack {
                stat("NEEDED", "\(req.quantityNeeded) units", Color.pantryTextDark)
                Spacer()
                stat("REMAINING", "\(req.quantityRemaining) units", .red)
                Spacer()
                stat("DEADLINE", req.deadline, Color.pantryTextDark)
            }
            if !closed {
                Divider().overlay(Color.pantryDivider)
                Button { Task { await viewModel.closeRequest(requestId: req.id) } } label: {
                    Text("Close Target Request").font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(.red, in: .rect(cornerRadius: 10))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pantrySurface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1))
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(Color.pantrySecondary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
        }
    }
}

// MARK: - Post Requests (FBPostRequestTab)

struct FBPostRequestView: View {
    @Bindable var viewModel: PantryLinkViewModel

    @State private var title = ""
    @State private var category = "Canned Foods"
    @State private var itemDesc = ""
    @State private var quantity = ""
    @State private var deadline = "2026-06-30"
    @State private var location = "12 Peachtree St NW, Atlanta, GA 30308"
    @State private var notes = ""
    @State private var postCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("✍️ Create Standardized Request",
                       "Ensure language is clear, descriptive, and follows uniform formats to reduce donor confusion.")

                field("Request Title (e.g. Bulk Canned Vegetables Needed)", text: $title)

                Text("Choose Approved Category").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PantryConstants.requestCategories, id: \.self) { cat in
                            let sel = category == cat
                            Button { category = cat } label: {
                                Text(cat).font(.system(size: 11.5, weight: sel ? .bold : .medium))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain).foregroundStyle(sel ? .white : Color.pantrySecondary)
                            .background(sel ? Color.pantryPrimary : Color.pantrySurface, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(sel ? .clear : Color.pantrySecondaryContainer, lineWidth: 1))
                        }
                    }
                }

                field("Standardized Approved Item Description", text: $itemDesc)
                VStack(alignment: .leading, spacing: 2) {
                    Text("❌ Not allowed: \"Need canned stuff\"").font(.system(size: 11)).foregroundStyle(.red)
                    Text("✅ Approved: \"Canned green beans, unopened, standard-sized cans\"")
                        .font(.system(size: 11)).foregroundStyle(Color.pantryPrimary)
                }

                HStack(spacing: 16) {
                    field("Quantity Needed", text: $quantity).keyboardType(.numberPad)
                    field("Deadline (YYYY-MM-DD)", text: $deadline)
                }
                field("Drop-Off Location (Partner Address)", text: $location)
                field("Handling Notes (Optional)", text: $notes)

                Button { submit() } label: {
                    Text("Compile & Post Standardized Request")
                        .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(Color.pantryPrimary)
            }
            .padding(16)
        }
        .sensoryFeedback(.success, trigger: postCount)
    }

    private func submit() {
        guard let qty = Int(quantity), qty > 0, !title.isEmpty, !itemDesc.isEmpty else {
            viewModel.showToast("Inputs validation failed. Title, description and numerical quantity are required!")
            return
        }
        Task {
            await viewModel.createRequest(title: title, category: category, itemDescription: itemDesc,
                                          quantityNeeded: qty, deadline: deadline,
                                          dropOffLocation: location, extraNotes: notes)
            title = ""; itemDesc = ""; quantity = ""
            postCount += 1
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14)).padding(12)
            .background(Color.pantrySurface, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1))
    }
}

// MARK: - Verify Deliveries (FBVerifyDropsTab)

struct FBVerifyDropsView: View {
    @Bindable var viewModel: PantryLinkViewModel
    @State private var rejectTarget: ClaimDTO?
    @State private var actionCount = 0

    private var drops: [ClaimDTO] { viewModel.allClaims.filter { $0.claimStatus == "Dropped Off" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("🛡️ Verify Incoming Donations",
                       "Validate delivered goods against request parameters. Approve or Reject carefully.")
                if drops.isEmpty {
                    EmptyStateCard(icon: "checkmark.seal", title: "No unconfirmed drop-offs.",
                                   subtitle: "Pantry counts are fully synced with actual deliveries.")
                } else {
                    ForEach(drops) { claim in dropCard(claim) }
                }
            }
            .padding(16)
        }
        .sensoryFeedback(.success, trigger: actionCount)
        .confirmationDialog("Confirm Delivery Rejection", isPresented: Binding(
            get: { rejectTarget != nil }, set: { if !$0 { rejectTarget = nil } }
        ), titleVisibility: .visible) {
            if let claim = rejectTarget {
                ForEach(PantryConstants.rejectionReasons, id: \.self) { reason in
                    Button(reason.capitalized) {
                        Task { await viewModel.reviewClaim(claimId: claim.id, approved: false, rejectionReason: reason) }
                        actionCount += 1; rejectTarget = nil
                    }
                }
                Button("Cancel", role: .cancel) { rejectTarget = nil }
            }
        } message: {
            Text("Every rejection must specify an approved reason.")
        }
    }

    private func dropCard(_ claim: ClaimDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(claim.requestTitle).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                    Text("Donor: \(claim.donorUserId)").font(.system(size: 12)).foregroundStyle(Color.pantrySecondary)
                }
                Spacer()
                Image(systemName: "shippingbox.and.arrow.backward.fill").foregroundStyle(Color.pantryPrimary)
            }
            Divider().overlay(Color.pantryDivider)
            HStack {
                Text("QUANTITY DELIVERED:").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.pantrySecondary)
                Spacer()
                Text("\(claim.quantityClaimed) units").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color.pantryPrimary)
            }
            HStack {
                Text("DROP DATE:").font(.system(size: 11)).foregroundStyle(Color.pantrySecondary)
                Spacer()
                Text(claim.dropoffConfirmationTimestamp.map { pantryFormatDate($0) } ?? "Today")
                    .font(.system(size: 12)).foregroundStyle(Color.pantryTextDark)
            }
            HStack(spacing: 12) {
                Button { rejectTarget = claim } label: {
                    Text("Reject Drop").font(.system(size: 13)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(.red)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.red.opacity(0.5), lineWidth: 1))
                Button {
                    Task { await viewModel.reviewClaim(claimId: claim.id, approved: true, rejectionReason: nil) }
                    actionCount += 1
                } label: {
                    Text("Approve & Recount").font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Color.pantryPrimary, in: .rect(cornerRadius: 10))
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pantrySurface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1))
    }
}

// MARK: - Audit Trail (FBAuditLogsTab)

struct FBAuditView: View {
    @Bindable var viewModel: PantryLinkViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("✒️ Permanent Audit Logs",
                       "Electronic traces of donor submissions, approvals, cancels and system releases.")
                if viewModel.auditLogs.isEmpty {
                    EmptyStateCard(icon: "clock.arrow.circlepath", title: "No actions logged yet.", subtitle: "")
                } else {
                    ForEach(viewModel.auditLogs) { log in logCard(log) }
                }
            }
            .padding(16)
        }
    }

    private func logCard(_ log: AuditLogDTO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(log.actionType).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                Spacer()
                Text(pantryFormatDate(log.timestamp)).font(.system(size: 10)).foregroundStyle(Color.pantryTextMuted)
            }
            Text("Donor: \(log.donorId)").font(.system(size: 11)).foregroundStyle(Color.pantryTextDark)
            Text("Request ID: #\(log.requestId)  |  Claim ID: #\(log.claimId)")
                .font(.system(size: 11)).foregroundStyle(Color.pantrySecondary)
            HStack(spacing: 4) {
                Text("Status:").font(.system(size: 11)).foregroundStyle(Color.pantryTextDark)
                Text(log.oldStatus).font(.system(size: 11)).foregroundStyle(Color.pantrySecondary)
                Text("➜").font(.system(size: 11))
                Text(log.newStatus).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.pantryPrimary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pantrySurface, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1))
    }
}

// MARK: - Profile (FBProfileTab)

struct FBProfileView: View {
    @Bindable var viewModel: PantryLinkViewModel

    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var city = ""
    @State private var zip = ""
    @State private var size = "Medium (100-500/wk)"
    @State private var hours = ""
    @State private var coldStorage = false
    @State private var loaded = false
    @State private var saveCount = 0
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("🏛️ Food Bank Profile", "Keep your public pantry details accurate for donors.")

                field("Agency Name", text: $name)
                field("Contact Phone", text: $phone).keyboardType(.phonePad)
                field("Street Address", text: $address)
                HStack(spacing: 12) {
                    field("City (GA)", text: $city)
                    field("ZIP", text: $zip).keyboardType(.numberPad)
                }

                Text("Facility size").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                ChipGrid(items: PantryConstants.foodBankSizes, columns: 1,
                         isSelected: { $0 == size }, onTap: { size = $0 })

                field("Operating Hours (e.g. Mon-Fri 9 AM - 5 PM)", text: $hours)

                HStack {
                    Image(systemName: "snowflake").foregroundStyle(Color.pantryPrimary)
                    Text("Refrigerated cold storage available").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $coldStorage).labelsHidden().tint(Color.pantryPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.pantrySurface, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1))

                Button { save() } label: {
                    Text("Save Profile").font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(Color.pantryPrimary)

                Button { viewModel.signOutUser() } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(Color.pantryPrimary)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pantryPrimary.opacity(0.5), lineWidth: 1))
                .accessibilityIdentifier("sign_out")

                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Text("Delete Account").font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(.red)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.red.opacity(0.5), lineWidth: 1))
            }
            .padding(16)
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .confirmationDialog("Delete your account permanently?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { _ = await viewModel.deleteUserAccount() } }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: loadProfile)
    }

    private func loadProfile() {
        guard !loaded, let p = viewModel.currentUserProfile else { return }
        name = p.name; phone = p.phone; address = p.fbAddress; city = p.fbCity; zip = p.fbZip
        if !p.fbSize.isEmpty { size = p.fbSize }
        hours = p.fbHours; coldStorage = p.fbColdStorage
        loaded = true
    }

    private func save() {
        Task {
            _ = await viewModel.updateProfile(name: name, phone: phone,
                fbAddress: address, fbCity: city, fbZip: zip, fbSize: size, fbHours: hours,
                fbColdStorage: coldStorage)
            saveCount += 1
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14)).padding(12)
            .background(Color.pantrySurface, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1))
    }
}

// MARK: - Shared header

// Short descriptor shown under the large navigation title (the title names the screen).
@ViewBuilder
private func header(_ title: String, _ subtitle: String) -> some View {
    Text(subtitle)
        .font(.system(size: 13)).foregroundStyle(Color.pantrySecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}
