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

    /// Cached coordinate for `address`, geocoding it once if needed. Tries the full address first,
    /// then progressively broader queries (drop the leading street component → city, GA zip → zip)
    /// so a hard-to-resolve exact street still yields a city/ZIP-level pin instead of no pin at all.
    /// Returns nil only if the address is empty or nothing resolves.
    func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let c = cache[key] { return c }
        if failed.contains(key) { return nil }

        // Build fallback queries: full → without street → … → last segment (usually "GA zip").
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var queries: [String] = []
        if parts.count <= 1 {
            queries = [address]
        } else {
            for start in 0..<parts.count { queries.append(parts[start...].joined(separator: ", ")) }
        }

        for query in queries {
            if let placemarks = try? await geocoder.geocodeAddressString(query),
               let loc = placemarks.first?.location {
                cache[key] = loc.coordinate
                return loc.coordinate
            }
        }
        failed.insert(key)
        return nil
    }
}
