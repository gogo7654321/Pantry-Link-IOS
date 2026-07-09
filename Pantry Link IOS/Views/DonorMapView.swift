//
//  DonorMapView.swift
//  Pantry Link IOS
//
//  Port of DonorMapTab. Native MapKit: food banks pinned at their (synced) coordinates,
//  pinch-to-zoom plus explicit +/− zoom controls, and one-tap directions in Apple or Google
//  Maps from the selected pantry's callout.
//

import SwiftUI
import MapKit

struct DonorMapView: View {
    @Bindable var viewModel: PantryLinkViewModel
    @State private var selected: FoodBankDTO?
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
                           span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2))
    )
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2))
    @State private var showDirections = false

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

            Map(position: $camera, selection: $selected) {
                // Food banks — green building pins (selectable).
                ForEach(viewModel.foodBanks) { fb in
                    Marker(fb.name, systemImage: "building.2.fill",
                           coordinate: CLLocationCoordinate2D(latitude: fb.latitude, longitude: fb.longitude))
                        .tint(Color.pantryPrimary)
                        .tag(fb)
                }
                // The donor's saved drop-off coordinates — distinct terracotta star pins.
                ForEach(viewModel.savedLocations) { loc in
                    let c = LocationHelper.coords(address: loc.address, zip: loc.zipCode)
                    Marker(loc.name, systemImage: "star.fill",
                           coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude))
                        .tint(Color.pantryTertiary)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapCompass(); MapScaleView() }   // pinch-to-zoom is on by default
            .onMapCameraChange(frequency: .continuous) { ctx in region = ctx.region }
            .overlay(alignment: .topTrailing) { zoomControls }
            .overlay(alignment: .bottom) {
                if let fb = selected {
                    callout(fb).padding(16).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: selected)
        }
        .confirmationDialog("Directions", isPresented: $showDirections, titleVisibility: .visible) {
            if let fb = selected {
                let coord = CLLocationCoordinate2D(latitude: fb.latitude, longitude: fb.longitude)
                let addr = "\(fb.address), \(fb.city), \(fb.state) \(fb.zipCode)"
                Button("Open in Apple Maps") { MapsLauncher.openAppleMaps(name: fb.name, coordinate: coord, address: addr) }
                Button("Open in Google Maps") { MapsLauncher.openGoogleMaps(coordinate: coord, address: addr) }
                Button("Cancel", role: .cancel) {}
            }
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

    private func callout(_ fb: FoodBankDTO) -> some View {
        let openNeeds = viewModel.requests.filter {
            $0.foodBankId == fb.id && $0.status != "Closed" && $0.status != "Confirmed by Food Bank"
        }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fb.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.pantryPrimary)
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.pantryTextMuted) }
            }
            Text("\(fb.address), \(fb.city), \(fb.state) \(fb.zipCode)")
                .font(.system(size: 12)).foregroundStyle(Color.pantryTextDark)
            HStack(spacing: 14) {
                Label(String(format: "%.1f mi", viewModel.getDistanceToFoodBank(fb)), systemImage: "car.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.pantryPrimary)
                Label("\(openNeeds) active needs", systemImage: "tray.full")
                    .font(.system(size: 12)).foregroundStyle(Color.pantrySecondary)
                if fb.coldStorage {
                    Label("Cold storage", systemImage: "snowflake").font(.system(size: 11)).foregroundStyle(Color(hex: 0x1976D2))
                }
            }
            if !fb.operatingHours.isEmpty {
                Label(fb.operatingHours, systemImage: "clock").font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted)
            }
            Button { showDirections = true } label: {
                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent).tint(Color.pantryPrimary).padding(.top, 2)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .pantryGlassCard(cornerRadius: 20)
    }
}
