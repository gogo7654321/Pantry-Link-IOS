//
//  GeocodeCache.swift
//  Pantry Link IOS
//
//  Turns a street address into a map coordinate on demand, via Apple's geocoder, and remembers
//  the result for the app's lifetime. The map uses this so pins follow the ADDRESS each pantry
//  entered (correctly formatted) rather than any stored coordinate — Apple resolves real Georgia
//  addresses reliably, and a lookup that fails simply yields no pin instead of a wrong one.
//

import Foundation
import CoreLocation

@MainActor
final class GeocodeCache {
    static let shared = GeocodeCache()

    private var cache: [String: CLLocationCoordinate2D] = [:]
    private var failed: Set<String> = []
    private let geocoder = CLGeocoder()

    /// Cached coordinate for `address`, geocoding it once if needed. Returns nil if the address is
    /// empty or Apple can't resolve it (so callers can skip the pin rather than place a wrong one).
    func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let c = cache[key] { return c }
        if failed.contains(key) { return nil }
        guard let placemarks = try? await geocoder.geocodeAddressString(address),
              let loc = placemarks.first?.location else {
            failed.insert(key)
            return nil
        }
        cache[key] = loc.coordinate
        return loc.coordinate
    }
}
