//
//  DonorWorkspaceView.swift
//  Pantry Link IOS
//
//  Donor workspace — native iOS 26 bottom TabView (system Liquid Glass tab bar), NavigationStacks
//  with large titles, and clean card-based screens. Ports DonorDashboardTab / DonorBrowseRequestsTab
//  / DonorClaimsTab with all Android logic intact (filters, claim flow, badges, status colors).
//

import SwiftUI

struct DonorWorkspaceView: View {
    @Bindable var viewModel: PantryLinkViewModel
    @State private var claimTarget: RequestDTO?

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "house.fill") {
                NavigationStack {
                    DonorDashboardView(viewModel: viewModel, claimTarget: $claimTarget)
                        .workspaceChrome("Dashboard", viewModel: viewModel)
                }
            }
            Tab("Needs", systemImage: "list.clipboard.fill") {
                NavigationStack {
                    DonorBrowseView(viewModel: viewModel, claimTarget: $claimTarget)
                        .workspaceChrome("Needs", viewModel: viewModel)
                        .searchable(text: Binding(get: { viewModel.searchQuery },
                                                  set: { viewModel.setSearchQuery($0) }),
                                    prompt: "Search food banks, items, cities")
                }
            }
            Tab("Map Finder", systemImage: "map.fill") {
                NavigationStack {
                    DonorMapView(viewModel: viewModel)
                        .workspaceChrome("Map Finder", large: false, viewModel: viewModel)
                }
            }
            Tab("My Claims", systemImage: "shippingbox.fill") {
                NavigationStack {
                    DonorClaimsView(viewModel: viewModel)
                        .workspaceChrome("My Claims", viewModel: viewModel)
                }
            }
            Tab("Account", systemImage: "person.crop.circle.fill") {
                NavigationStack {
                    DonorAccountView(viewModel: viewModel)
                        .workspaceChrome("Account", viewModel: viewModel)
                }
            }
        }
        .tint(Color.pantryPrimary)
        .task { await viewModel.refreshAll() }
        .sheet(item: $claimTarget) { req in ClaimSheet(viewModel: viewModel, request: req) }
    }
}

// MARK: - Dashboard

struct DonorDashboardView: View {
    @Bindable var viewModel: PantryLinkViewModel
    @Binding var claimTarget: RequestDTO?

    private var openRequests: [RequestDTO] {
        viewModel.requests.filter { $0.status != "Closed" && $0.status != "Confirmed by Food Bank" }
    }
    private var activeClaims: Int {
        viewModel.claims.filter { $0.claimStatus == "Claimed" || $0.claimStatus == "Ready for Drop-Off" }.count
    }
    private var itemsDonated: Int {
        viewModel.claims.filter { $0.claimStatus == "Accepted" }.reduce(0) { $0 + $1.quantityClaimed }
    }
    private var userName: String {
        let n = viewModel.currentUserProfile?.name ?? ""
        if !n.isEmpty { return n }
        let email = viewModel.currentUserEmail
        return email.isEmpty ? "Neighbor" : String(email.prefix(while: { $0 != "@" }))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome card (soft green)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome back,").font(.system(size: 15)).foregroundStyle(.secondary)
                    Text(userName).font(.system(size: 26, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                    Text("Your community needs you today. Check local requests to make an immediate impact.")
                        .font(.system(size: 15)).foregroundStyle(Color.pantryTextDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pantryPrimaryContainer.opacity(0.6), in: .rect(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image("app_logo").resizable().scaledToFit()
                        .frame(width: 52, height: 52).padding(14).opacity(0.9)
                }

                // Stat tiles
                HStack(spacing: 14) {
                    StatTile(icon: "shippingbox.fill", iconColor: Color(hex: 0xE0A83E),
                             value: "\(activeClaims)", label: "Active Claims")
                    StatTile(icon: "heart.fill", iconColor: Color.pantryPrimary,
                             value: "\(itemsDonated)", label: "Items Donated")
                }

                HStack {
                    Text("Urgent Needs Near You").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.pantryTextDark)
                    Spacer()
                }

                if openRequests.isEmpty {
                    EmptyStateCard(icon: "leaf.fill", title: "All caught up!",
                                   subtitle: "No urgent requests in your area right now.")
                } else {
                    ForEach(openRequests.prefix(5)) { req in
                        RequestCard(request: req, distance: distance(for: req)) { claimTarget = req }
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    private func distance(for req: RequestDTO) -> Double {
        guard let fb = viewModel.foodBanks.first(where: { $0.id == req.foodBankId }) else { return 0 }
        return viewModel.getDistanceToFoodBank(fb)
    }
}

// MARK: - Browse (Needs)

struct DonorBrowseView: View {
    @Bindable var viewModel: PantryLinkViewModel
    @Binding var claimTarget: RequestDTO?

    private var filtered: [RequestDTO] {
        let cat = viewModel.selectedCategoryFilter
        let q = viewModel.searchQuery
        return viewModel.requests.filter { req in
            let matchesCategory = cat == "All" || req.category == cat
            let matchesSearch = q.isEmpty
                || req.title.localizedCaseInsensitiveContains(q)
                || req.itemDescription.localizedCaseInsensitiveContains(q)
                || req.foodBankName.localizedCaseInsensitiveContains(q)
            let notClosed = req.status != "Closed" && req.status != "Confirmed by Food Bank"
            return matchesCategory && matchesSearch && notClosed
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PantryConstants.browseCategories, id: \.self) { cat in
                            let sel = viewModel.selectedCategoryFilter == cat
                            Button { viewModel.setCategoryFilter(cat) } label: {
                                Text(cat).font(.system(size: 12.5, weight: sel ? .bold : .medium))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(sel ? .white : Color.pantrySecondary)
                            .background(sel ? Color.pantryPrimary : Color.pantrySurface, in: .capsule)
                            .overlay(Capsule().strokeBorder(sel ? .clear : Color.pantryBorder, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 2)
                }

                if filtered.isEmpty {
                    EmptyStateCard(icon: "tray", title: "No matching active requests.",
                                   subtitle: "Try clearing search or picking another category.")
                        .padding(.top, 40)
                } else {
                    ForEach(filtered) { req in
                        RequestCard(request: req, distance: distance(for: req)) { claimTarget = req }
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }

    private func distance(for req: RequestDTO) -> Double {
        guard let fb = viewModel.foodBanks.first(where: { $0.id == req.foodBankId }) else { return 0 }
        return viewModel.getDistanceToFoodBank(fb)
    }
}

// MARK: - My Claims

struct DonorClaimsView: View {
    @Bindable var viewModel: PantryLinkViewModel

    private var acceptedCount: Int { viewModel.claims.filter { $0.claimStatus == "Accepted" }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BadgeHeader(acceptedCount: acceptedCount, total: viewModel.claims.count)
                if viewModel.claims.isEmpty {
                    EmptyStateCard(icon: "bookmark", title: "No claims yet.",
                                   subtitle: "Browse active needs and commit to bring supplies.")
                        .padding(.top, 20)
                } else {
                    ForEach(viewModel.claims) { claim in
                        ClaimCard(
                            claim: claim,
                            foodBank: viewModel.foodBanks.first { $0.name == claim.foodBankName },
                            onCancel: { Task { await viewModel.cancelClaim(claimId: claim.id) } },
                            onDropOff: { Task { await viewModel.dropOffClaim(claimId: claim.id) } },
                            onExpire: { Task { await viewModel.triggerClaimExpiration(claimId: claim.id) } }
                        )
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Reusable pieces

struct StatTile: View {
    let icon: String; let iconColor: Color; let value: String; let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(iconColor)
            Text(value).font(.system(size: 34, weight: .bold)).foregroundStyle(Color.pantryTextDark)
            Text(label).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.pantrySurface, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.pantryBorder.opacity(0.7), lineWidth: 1))
    }
}

struct EmptyStateCard: View {
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(Color.pantrySecondary.opacity(0.55))
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.pantryTextDark)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 20)
        .background(Color.pantrySurface, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.pantryBorder.opacity(0.7), lineWidth: 1))
    }
}

func pantryFormatDate(_ ms: Int64) -> String {
    let date = Date(timeIntervalSince1970: Double(ms) / 1000)
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM dd, yyyy HH:mm"
    return fmt.string(from: date)
}

func categorySymbol(_ category: String) -> String {
    switch category {
    case "Canned Foods": return "takeoutbag.and.cup.and.straw"
    case "Hygiene Products": return "hands.and.sparkles"
    case "Baby Supplies": return "figure.and.child.holdinghands"
    case "School Supplies": return "backpack"
    default: return "fork.knife"
    }
}
