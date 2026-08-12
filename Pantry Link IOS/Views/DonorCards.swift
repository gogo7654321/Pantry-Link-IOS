//
//  DonorCards.swift
//  Pantry Link IOS
//
//  Ports of ItemRequestCard, the claim AlertDialog, DonorClaimCard and the badge header
//  (PantryLinkWidgets.kt). Claim validation, badge tiers and status colors match Android.
//

import SwiftUI
import CoreLocation
import PhotosUI

// MARK: - Request card (ItemRequestCard)

struct RequestCard: View {
    let request: RequestDTO
    let distance: Double
    let onClaim: () -> Void

    // Only "fulfilled" when the request actually asked for something and none remains — a request
    // with a missing/zero quantityNeeded must NOT read as fully fulfilled when nobody claimed it.
    private var fulfilled: Bool { request.quantityNeeded > 0 && request.quantityRemaining <= 0 }
    private var progress: Double {
        request.quantityNeeded > 0
            ? Double(request.quantityNeeded - request.quantityRemaining) / Double(request.quantityNeeded)
            : 1
    }
    private var committed: Int { request.quantityNeeded - request.quantityRemaining }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title).font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.pantryPrimary)
                    Label(request.foodBankName, systemImage: "building.2")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.pantrySecondary)
                        .labelStyle(.titleAndIcon)
                    if AmazonLink.isValid(request.amazonUrl) {
                        Label("Amazon fulfillment", systemImage: "cart.fill")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.pantryTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.pantryTertiary.opacity(0.12), in: .capsule)
                    }
                }
                Spacer()
                Label(request.category.uppercased(), systemImage: categorySymbol(request.category))
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.pantryTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.pantryTertiary.opacity(0.12), in: .rect(cornerRadius: 12))
            }
            Divider().overlay(Color.pantryDivider)

            Text("SPECIFIC PANTRIES NEED:").font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Color.pantrySecondary).kerning(0.8)
            Text(request.itemDescription).font(.system(size: 13.5)).foregroundStyle(Color.pantryTextDark.opacity(0.85))

            // Progress
            HStack(spacing: 8) {
                Text(fulfilled ? "FULLY FULFILLED" : "\(request.quantityRemaining) NEEDED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(fulfilled ? Color.pantryPrimary : Color.pantrySecondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background((fulfilled ? Color.pantryPrimary.opacity(0.12) : Color(hex: 0xF5EDE4)), in: .rect(cornerRadius: 8))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.pantrySecondaryContainer).frame(height: 8)
                        Capsule().fill(fulfilled ? Color.pantryPrimary : Color.pantryTertiary)
                            .frame(width: max(0, geo.size.width * progress), height: 8)
                    }
                }
                .frame(height: 8)
                Text("\(committed) of \(request.quantityNeeded)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pantrySecondary)
            }
            .frame(height: 20)

            if committed > 0 && !fulfilled {
                Label("\(committed) units already committed/fulfilled by neighbors!",
                      systemImage: "hands.sparkles.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0x047857))
            }

            Divider().overlay(Color.pantryDivider)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(String(format: "%.1f miles away", distance), systemImage: "car.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                    Label("Due: \(request.deadline)", systemImage: "calendar")
                        .font(.system(size: 11.5)).foregroundStyle(Color.pantrySecondary)
                }
                Spacer()
                Button(action: onClaim) {
                    Text(fulfilled ? "Review Need" : "Help Fulfill")
                        .font(.system(size: 12, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 8)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(fulfilled ? Color.pantrySecondary : Color.pantryPrimary, in: .rect(cornerRadius: 12))
            }
        }
        .padding(18)
        .background(Color.pantrySurface, in: .rect(topLeadingRadius: 24, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 8))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 8)
            .strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1.2))
    }
}

// MARK: - Claim sheet (the claim AlertDialog)

struct ClaimSheet: View {
    @Bindable var viewModel: PantryLinkViewModel
    let request: RequestDTO
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var error: String?

    // Amazon fulfillment
    @State private var showSafari = false
    @State private var receiptItem: PhotosPickerItem?
    @State private var receiptPreview: UIImage?
    @State private var receiptBase64: String?
    @State private var processing = false

    private var amazonURL: URL? { AmazonLink.normalized(request.amazonUrl) }
    private var isAmazon: Bool { amazonURL != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    info("Title", request.title)
                    info("Category", request.category)
                    info("Vetted Requirements", request.itemDescription)
                    info("Pantry", request.foodBankName)
                    info(isAmazon ? "Ship-To Address" : "Drop-Off", request.dropOffLocation)
                    info("Deadline Date", request.deadline)
                    if !request.extraNotes.isEmpty { info("Special Notes", request.extraNotes) }
                    Divider().overlay(Color.pantryDivider)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Needed Today").font(.system(size: 11)).foregroundStyle(Color.pantrySecondary)
                            Text("\(request.quantityNeeded) units").font(.system(size: 16, weight: .bold))
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Remaining").font(.system(size: 11)).foregroundStyle(Color.pantrySecondary)
                            Text("\(request.quantityRemaining) remaining")
                                .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                        }
                    }

                    Text(isAmazon ? "How many will you buy & ship?" : "Enter amount you commit to bring:")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.numberPad)
                        .padding(12).background(Color.pantryFieldFill, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.pantryBorder, lineWidth: 1))

                    if isAmazon { amazonSection }

                    if let error {
                        Text("⚠️ \(error)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                    }

                    Text(isAmazon
                         ? "Buy the item on Amazon, ship it to the address above, then upload your order confirmation so the pantry can verify it."
                         : "Note: Once you accept, these items are reserved. You must deliver them to the pantry in person before the deadline.")
                        .font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted)
                }
                .padding(20)
            }
            .navigationTitle(isAmazon ? "Fulfill via Amazon" : "Claim Assistance Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if processing {
                        ProgressView()
                    } else {
                        Button(isAmazon ? "Submit" : "Reserve & Accept") { submit() }.fontWeight(.bold)
                    }
                }
            }
        }
        .sheet(isPresented: $showSafari) { if let amazonURL { SafariView(url: amazonURL) } }
        .onChange(of: receiptItem) { _, newItem in Task { await loadReceipt(newItem) } }
        .onAppear {
            // clampDefaultClaimQuantity: min(remaining, 5)
            quantity = String(request.quantityRemaining < 5 ? request.quantityRemaining : 5)
        }
    }

    // MARK: Amazon section (view listing in-app + upload order confirmation)

    private var amazonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showSafari = true } label: {
                Label("View item on Amazon", systemImage: "cart.fill")
                    .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent).tint(Color.pantryTertiary)

            Text("AFTER ORDERING, UPLOAD YOUR CONFIRMATION")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.pantrySecondary).kerning(0.5)

            if let receiptPreview {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: receiptPreview)
                        .resizable().scaledToFit().frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pantryBorder, lineWidth: 1))
                    PhotosPicker(selection: $receiptItem, matching: .images) {
                        Text("Change").font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(8)
                }
            } else {
                PhotosPicker(selection: $receiptItem, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 16))
                        Text("Upload order confirmation / receipt").font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color.pantryPrimary)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.pantryFieldFill, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pantryPrimary.opacity(0.4),
                                                                             style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
            }
        }
        .padding(12)
        .background(Color.pantryTertiary.opacity(0.06), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1))
    }

    private func loadReceipt(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        error = nil
        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
            receiptPreview = img
            receiptBase64 = ReceiptImage.encode(img)
            if receiptBase64 == nil { error = "Couldn't process that image — try another." }
        } else {
            error = "Couldn't load that image — try another."
        }
    }

    private func submit() {
        guard let qty = Int(quantity), qty > 0 else {
            error = "Please enter a valid amount greater than 0."; return
        }
        if qty > request.quantityRemaining {
            error = "You cannot claim more than the remaining quantity (\(request.quantityRemaining))."; return
        }
        if isAmazon {
            guard let receipt = receiptBase64 else {
                error = "Please upload your Amazon order confirmation first."; return
            }
            processing = true
            Task {
                let (ok, msg) = await viewModel.fulfillViaAmazon(requestId: request.id, quantity: qty, receiptImage: receipt)
                processing = false
                if ok { dismiss() } else { error = msg }
            }
        } else {
            Task {
                let (ok, msg) = await viewModel.claimRequest(requestId: request.id, quantity: qty)
                if ok { dismiss() } else { error = msg }
            }
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.pantrySecondary)
            Text(value).font(.system(size: 13)).foregroundStyle(Color.pantryTextDark)
        }
    }
}

// MARK: - Claim card (DonorClaimCard)

struct ClaimCard: View {
    let claim: ClaimDTO
    let foodBank: FoodBankDTO?
    let onCancel: () -> Void
    let onDropOff: () -> Void
    @State private var showDirections = false

    private var statusColor: Color {
        switch claim.claimStatus {
        case "Claimed": return Color.pantryPrimary
        case "Ready for Drop-Off": return Color(hex: 0xF57C00)
        case "Dropped Off": return Color.pantryInfo
        case "Accepted": return Color(hex: 0x2E7D32)
        case "Rejected": return .red
        default: return Color.pantryTextMuted
        }
    }
    private var actionable: Bool {
        claim.claimStatus == "Claimed" || claim.claimStatus == "Ready for Drop-Off"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(claim.requestTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                    Label(claim.foodBankName, systemImage: "building.2")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.pantrySecondary)
                    if let fb = foodBank {
                        Text("\(fb.address), \(fb.city), \(fb.state) \(fb.zipCode)")
                            .font(.system(size: 11.5)).foregroundStyle(Color.pantryTextMuted)
                    }
                }
                Spacer()
                Text(claim.claimStatus.uppercased())
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(statusColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(statusColor.opacity(0.12), in: .rect(cornerRadius: 10))
            }
            Divider().overlay(Color.pantryDivider)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("COMMITTED AMOUNT").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.pantrySecondary)
                    Text("\(claim.quantityClaimed) Units").font(.system(size: 13.5, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("RESERVED ON").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.pantrySecondary)
                    Text(pantryFormatDate(claim.claimTimestamp)).font(.system(size: 13.5)).foregroundStyle(Color.pantryTextDark)
                }
            }

            if let reason = claim.rejectionReason, claim.claimStatus == "Rejected" {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("REJECTION REASON:").font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                        Text(reason).font(.system(size: 12)).foregroundStyle(Color.pantryTextDark)
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 10))
            }

            if actionable {
                if let fb = foodBank {
                    Button { showDirections = true } label: {
                        Label("Get Navigation Directions", systemImage: "location.fill")
                            .font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color(hex: 0x047857))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: 0xA7F3D0), lineWidth: 1))
                    .confirmationDialog("Directions", isPresented: $showDirections, titleVisibility: .visible) {
                        Button("Open in Apple Maps") { MapsLauncher.openAppleMaps(name: fb.name, address: fb.fullAddress) }
                        Button("Open in Google Maps") { MapsLauncher.openGoogleMaps(address: fb.fullAddress) }
                        Button("Cancel", role: .cancel) {}
                    }
                }
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel Claim").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain).foregroundStyle(.red)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.red.opacity(0.5), lineWidth: 1))
                    Button(action: onDropOff) {
                        Text("Mark Dropped Off").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .background(Color.pantryPrimary, in: .rect(cornerRadius: 10))
                }
            }
        }
        .padding(18)
        .background(Color.pantrySurface, in: .rect(topLeadingRadius: 6, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 24))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 24)
            .strokeBorder(Color.pantrySecondaryContainer, lineWidth: 1.2))
    }
}

// MARK: - Badge header (getBadgeInfo)

struct BadgeInfo {
    let title: String; let container: Color; let text: Color
    let required: Int; let nextTitle: String?; let nextRequired: Int?; let symbol: String
}

func getBadgeInfo(_ accepted: Int) -> BadgeInfo {
    switch accepted {
    case 25...: return BadgeInfo(title: "Hunger Hero", container: Color(hex: 0xFEE2E2), text: Color(hex: 0xB91C1C), required: 25, nextTitle: nil, nextRequired: nil, symbol: "hand.thumbsup.fill")
    case 10...: return BadgeInfo(title: "Vetted Community Donor", container: Color(hex: 0xD1FAE5), text: Color(hex: 0x047857), required: 10, nextTitle: "Hunger Hero", nextRequired: 25, symbol: "checkmark.seal.fill")
    case 5...:  return BadgeInfo(title: "Generous Giver", container: Color(hex: 0xE0F2FE), text: Color(hex: 0x0369A1), required: 5, nextTitle: "Vetted Community Donor", nextRequired: 10, symbol: "heart.fill")
    case 1...:  return BadgeInfo(title: "Kind Contributor", container: Color(hex: 0xE0E7FF), text: Color(hex: 0x4338CA), required: 1, nextTitle: "Generous Giver", nextRequired: 5, symbol: "hands.sparkles.fill")
    default:    return BadgeInfo(title: "Pantry Pioneer", container: Color(hex: 0xF1F5F9), text: Color(hex: 0x475569), required: 0, nextTitle: "Kind Contributor", nextRequired: 1, symbol: "star.fill")
    }
}

struct BadgeHeader: View {
    let acceptedCount: Int
    let total: Int
    private var badge: BadgeInfo { getBadgeInfo(acceptedCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: badge.symbol).font(.system(size: 22)).foregroundStyle(badge.text)
                VStack(alignment: .leading, spacing: 1) {
                    Text(badge.title).font(.system(size: 15, weight: .heavy)).foregroundStyle(badge.text)
                    Text("\(acceptedCount) accepted • \(total) total claims")
                        .font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted)
                }
                Spacer()
            }
            if let nextTitle = badge.nextTitle, let nextReq = badge.nextRequired {
                let remaining = max(0, nextReq - acceptedCount)
                Text("\(remaining) more accepted \(remaining == 1 ? "drop-off" : "drop-offs") to reach \(nextTitle)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.pantrySecondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(badge.container, in: .rect(cornerRadius: 18))
    }
}
