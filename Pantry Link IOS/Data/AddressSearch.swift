//
//  AddressSearch.swift
//  Pantry Link IOS
//
//  Native address autocomplete built on MapKit's MKLocalSearchCompleter (no API key required,
//  no Google dependency). Feeds live suggestions as the user types, and resolves a chosen
//  suggestion to a precise coordinate + structured address so saved drop-off locations pin
//  exactly and never rely on the ZIP approximation table.
//

import Foundation
import MapKit
import SwiftUI

/// A suggestion resolved to a precise coordinate and clean address components.
struct ResolvedAddress: Sendable, Equatable {
    let street: String
    let city: String
    let state: String
    let zip: String
    let latitude: Double
    let longitude: Double

    /// A single-line address for display / storage.
    var oneLine: String {
        var parts = [street]
        let cityState = [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
        if !cityState.isEmpty { parts.append(cityState) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

@MainActor
@Observable
final class AddressSearchModel: NSObject, MKLocalSearchCompleterDelegate {

    /// The current query text; setting it drives the completer.
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { suggestions = [] } else { completer.queryFragment = trimmed }
        }
    }

    private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Bias results toward Georgia so nearby matches rank first.
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
            span: MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0))
    }

    func clear() {
        query = ""
        suggestions = []
    }

    // MKLocalSearchCompleter delivers these on the main thread; assumeIsolated keeps us on the
    // MainActor without hopping (which would require the non-Sendable results to cross actors).
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { self.suggestions = completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.suggestions = [] }
    }

    /// Resolve a chosen suggestion to a precise coordinate + structured address.
    func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedAddress? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let placemark = response.mapItems.first?.placemark else { return nil }
        let coord = placemark.coordinate
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        return ResolvedAddress(
            street: street.isEmpty ? completion.title : street,
            city: placemark.locality ?? "",
            state: placemark.administrativeArea ?? "",
            zip: placemark.postalCode ?? "",
            latitude: coord.latitude,
            longitude: coord.longitude)
    }
}

// MARK: - Reusable autocomplete field (used on the sign-up form)

/// A `PantryField` wired to live MapKit address autocomplete. As the user types, suggestions
/// appear beneath it; tapping one fills the field with a clean street line and calls `onResolved`
/// with the structured city/state/ZIP + exact coordinates so callers can populate related fields.
struct AddressAutocompleteField: View {
    let title: String
    var systemImage: String? = "mappin.and.ellipse"
    @Binding var text: String
    var onResolved: (ResolvedAddress) -> Void
    @State private var search = AddressSearchModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PantryField(title: title, systemImage: systemImage,
                        text: Binding(get: { text }, set: { text = $0; search.query = $0 }))
                .autocorrectionDisabled()
            if !search.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(search.suggestions.prefix(4).enumerated()), id: \.offset) { _, s in
                        Button { Task { await pick(s) } } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.pantryTextDark)
                                if !s.subtitle.isEmpty {
                                    Text(s.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(Color.pantrySurface, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pantryBorder, lineWidth: 1))
            }
        }
    }

    private func pick(_ s: MKLocalSearchCompletion) async {
        guard let r = await search.resolve(s) else { return }
        text = r.street
        onResolved(r)
        search.clear()
    }
}
