//
//  DonorMapView.swift
//  Pantry Link IOS
//
//  Port of DonorMapTab. Native MapKit: food banks pinned at their (synced) coordinates and the
//  donor's own saved drop-off locations pinned as terracotta stars. Both are tappable and offer
//  one-tap directions in Apple or Google Maps; saved pins also surface their notes.
//

import SwiftUI
import MapKit

struct DonorMapView: View {
    @Bindable var viewModel: PantryLinkViewModel

    /// A unified, Hashable selection so both food banks and saved locations can be tapped on the
    /// same map (Map(selection:) needs one tag type). We store the id and resolve to the model.
    private enum MapPin: Hashable {
        case foodBank(Int)
        case saved(Int)
    }

    /// Target for the "open in Maps" dialog — just a name + address (Maps geocodes the address).
    private struct DirTarget: Identifiable {
        let id = UUID()
        let name: String
        let address: String
    }

    @State private var selection: MapPin?
    @State private var dirTarget: DirTarget?
    @State private var claimTarget: RequestDTO?
    /// Pin coordinates resolved from each pantry/saved-location ADDRESS (keyed by full address).
    @State private var pinCoords: [String: CLLocationCoordinate2D] = [:]
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
                           span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2))
    )
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2))

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.hasLocationPermission ? "location.fill" : "mappin.and.ellipse")
                    .foregroundStyle(Color.pantryPrimary)
                Text(viewModel.hasLocationPermission ? "Showing pantries near you" : "ZIP mode • \(viewModel.userZipCode)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.pantryTextDark)
                Spacer()
                Label("Pantries", systemImage: "building.2.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                if !viewModel.savedLocations.isEmpty {
                    Label("Saved", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.pantryTertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Map(position: $camera, selection: $selection) {
                // Food banks — pinned at the coordinate geocoded from their ADDRESS (not stored coords).
                ForEach(viewModel.foodBanks) { fb in
                    if let coord = pinCoords[fb.fullAddress] {
                        let count = openRequests(for: fb).count
                        Annotation(fb.name, coordinate: coord) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.pantryPrimary, in: Circle())
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                        .background(Color.pantryTertiary, in: Capsule())
                                        .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .tag(MapPin.foodBank(fb.id))
                    }
                }
                // The donor's saved drop-off locations — pinned from their address too.
                ForEach(viewModel.savedLocations) { loc in
                    if let coord = pinCoords[loc.fullAddress] {
                        Marker(loc.name, systemImage: "star.fill", coordinate: coord)
                            .tint(Color.pantryTertiary)
                            .tag(MapPin.saved(loc.id))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapCompass(); MapScaleView() }   // pinch-to-zoom is on by default
            .onMapCameraChange(frequency: .continuous) { ctx in region = ctx.region }
            .overlay(alignment: .topTrailing) { zoomControls }
            .overlay(alignment: .bottom) { calloutOverlay }
            .animation(.easeInOut, value: selection)
            .task(id: pinResolveKey) { await resolvePins() }
        }
        .confirmationDialog("Directions",
                            isPresented: Binding(get: { dirTarget != nil }, set: { if !$0 { dirTarget = nil } }),
                            presenting: dirTarget) { t in
            Button("Open in Apple Maps") { MapsLauncher.openAppleMaps(name: t.name, address: t.address) }
            Button("Open in Google Maps") { MapsLauncher.openGoogleMaps(address: t.address) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $claimTarget) { req in ClaimSheet(viewModel: viewModel, request: req) }
    }

    /// A key that changes whenever the set of addresses changes, so pins re-resolve on data load.
    private var pinResolveKey: String {
        (viewModel.foodBanks.map(\.fullAddress) + viewModel.savedLocations.map(\.fullAddress))
            .sorted().joined(separator: "|")
    }

    /// Geocode every pantry / saved-location ADDRESS into a pin coordinate (cached, one-time each).
    private func resolvePins() async {
        let addresses = Set(
            (viewModel.foodBanks.map(\.fullAddress) + viewModel.savedLocations.map(\.fullAddress))
                .filter { !$0.isEmpty })
        for addr in addresses where pinCoords[addr] == nil {
            if let coord = await GeocodeCache.shared.coordinate(for: addr) {
                pinCoords[addr] = coord
            }
        }
    }

    @ViewBuilder
    private var calloutOverlay: some View {
        switch selection {
        case .foodBank(let id):
            if let fb = viewModel.foodBanks.first(where: { $0.id == id }) {
                foodBankCallout(fb).padding(16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .saved(let id):
            if let loc = viewModel.savedLocations.first(where: { $0.id == id }) {
                savedCallout(loc).padding(16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        case .none:
            EmptyView()
        }
    }

    // Explicit zoom controls (glass control cluster, in addition to pinch-to-zoom)
    private var zoomControls: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(spacing: 8) {
                Button { zoom(by: 0.5) } label: { Image(systemName: "plus").frame(width: 36, height: 36) }
                    .buttonStyle(.glass)
                Button { zoom(by: 2.0) } label: { Image(systemName: "minus").frame(width: 36, height: 36) }
                    .buttonStyle(.glass)
            }
            .font(.system(size: 16, weight: .bold))
            .tint(Color.pantryPrimary)
        }
        .padding(12)
    }

    private func zoom(by factor: Double) {
        let newSpan = MKCoordinateSpan(
            latitudeDelta: min(max(region.span.latitudeDelta * factor, 0.005), 60),
            longitudeDelta: min(max(region.span.longitudeDelta * factor, 0.005), 60))
        withAnimation(.easeInOut) {
            camera = .region(MKCoordinateRegion(center: region.center, span: newSpan))
        }
    }

    private func openRequests(for fb: FoodBankDTO) -> [RequestDTO] {
        viewModel.requests.filter {
            $0.foodBankId == fb.id && $0.status != "Closed" && $0.status != "Confirmed by Food Bank"
        }
    }

    private func foodBankCallout(_ fb: FoodBankDTO) -> some View {
        let needs = openRequests(for: fb)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fb.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.pantryPrimary)
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.pantryTextMuted) }
            }
            Text(fb.fullAddress)
                .font(.system(size: 12)).foregroundStyle(Color.pantryTextDark)
            HStack(spacing: 14) {
                Label(String(format: "%.1f mi", viewModel.getDistanceToFoodBank(fb)), systemImage: "car.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                Label("\(needs.count) active needs", systemImage: "tray.full")
                    .font(.system(size: 12)).foregroundStyle(Color.pantrySecondary)
                if fb.coldStorage {
                    Label("Cold storage", systemImage: "snowflake").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.pantryInfo)
                }
            }
            if !fb.operatingHours.isEmpty {
                Label(fb.operatingHours, systemImage: "clock").font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted)
            }
            // This pantry's open requests — tap one to claim it.
            if !needs.isEmpty {
                Divider().overlay(Color.pantryDivider)
                Text("THEIR REQUESTS").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.pantrySecondary)
                ForEach(needs.prefix(3)) { req in
                    Button { selection = nil; claimTarget = req } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(req.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.pantryTextDark)
                                Text("\(req.quantityRemaining) of \(req.quantityNeeded) needed • \(req.category)")
                                    .font(.system(size: 10.5)).foregroundStyle(Color.pantrySecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(Color.pantryFieldFill, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                if needs.count > 3 {
                    Text("+\(needs.count - 3) more in Needs").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.pantryPrimary)
                }
            }
            Button {
                dirTarget = DirTarget(name: fb.name, address: fb.fullAddress)
            } label: {
                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent).tint(Color.pantryPrimary).padding(.top, 2)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .pantryGlassCard(cornerRadius: 20)
    }

    private func savedCallout(_ loc: SavedLocation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(loc.name, systemImage: "star.fill").font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.pantryTertiary)
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.pantryTextMuted) }
            }
            if !loc.address.isEmpty {
                Text(loc.zipCode.isEmpty ? loc.address : "\(loc.address) (\(loc.zipCode))")
                    .font(.system(size: 12)).foregroundStyle(Color.pantryTextDark)
            }
            if !loc.notes.isEmpty {
                Label(loc.notes, systemImage: "note.text")
                    .font(.system(size: 12)).foregroundStyle(Color.pantrySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                dirTarget = DirTarget(name: loc.name, address: loc.fullAddress)
            } label: {
                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent).tint(Color.pantryTertiary).padding(.top, 2)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .pantryGlassCard(cornerRadius: 20)
    }
}
