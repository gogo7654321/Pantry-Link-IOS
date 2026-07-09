//
//  LocationHelper.swift
//  Pantry Link IOS
//
//  Port of com.example.data.LocationHelper.kt.
//  The Android version tries a synchronous Android Geocoder first, then falls back to a
//  deterministic address/ZIP → coordinate table. iOS's CLGeocoder is async-only, so this
//  port implements the deterministic fallback table verbatim (the branch that actually
//  runs on the emulator, and the one covered by tests). A CLGeocoder "precise" path can be
//  layered on later without changing these results.
//

import Foundation

struct GeoCoord: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
}

enum LocationHelper {

    /// Kotlin: getCoordsForAddressWithContext(...) fallback branch (context == nil path).
    static func coords(address: String, zip: String) -> GeoCoord {
        let addrLower = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let zipTrim = zip.trimmingCharacters(in: .whitespacesAndNewlines)

        func has(_ s: String) -> Bool { addrLower.contains(s) }

        switch true {
        case has("smyrna"), has("cobb pkwy"), zipTrim == "30080", zipTrim == "30082":
            return GeoCoord(latitude: 33.8821, longitude: -84.4811)
        case has("kennesaw"), zipTrim == "30144", zipTrim == "30152", has("ksu"):
            return GeoCoord(latitude: 34.0234, longitude: -84.6155)
        case has("acworth"), zipTrim == "30101", zipTrim == "30102":
            return GeoCoord(latitude: 34.0659, longitude: -84.6769)
        case has("woodstock"), zipTrim == "30188", zipTrim == "30189":
            return GeoCoord(latitude: 34.1013, longitude: -84.5194)
        case has("marietta"), has("powder springs"), zipTrim == "30064", zipTrim == "30060", zipTrim == "30008":
            return GeoCoord(latitude: 33.9407, longitude: -84.5587)
        case has("sandy springs"), has("abernathy"), zipTrim == "30328", zipTrim == "30350":
            return GeoCoord(latitude: 33.9379, longitude: -84.3486)
        case has("roswell"), has("atlanta st"), zipTrim == "30075", zipTrim == "30076":
            return GeoCoord(latitude: 34.0175, longitude: -84.3612)
        case has("1722 peachtree"), zipTrim == "30309":
            return GeoCoord(latitude: 33.8016, longitude: -84.3897)
        case has("75 piedmont"), zipTrim == "30303":
            return GeoCoord(latitude: 33.7563, longitude: -84.3853)
        case has("marietta blvd"), zipTrim == "30318":
            return GeoCoord(latitude: 33.7885, longitude: -84.4285)
        case has("ponce de leon"), zipTrim == "30308", zipTrim == "30344":
            return GeoCoord(latitude: 33.7725, longitude: -84.3663)
        case has("1280 west peachtree"):
            return GeoCoord(latitude: 33.7903, longitude: -84.3879)
        case has("northside"), zipTrim == "30314":
            return GeoCoord(latitude: 33.7569, longitude: -84.4079)
        case zipTrim == "30507", zipTrim == "30501":
            return GeoCoord(latitude: 34.2582, longitude: -83.8185)   // Gainesville
        case zipTrim == "30909":
            return GeoCoord(latitude: 33.4735, longitude: -82.0649)   // Augusta
        case zipTrim == "31401":
            return GeoCoord(latitude: 32.0809, longitude: -81.0912)   // Savannah
        case zipTrim == "30601", zipTrim == "30605", zipTrim == "30606":
            return GeoCoord(latitude: 33.9519, longitude: -83.3576)   // Athens
        default:
            return coordsForZip(zip)
        }
    }

    /// Kotlin: getCoordsForZip(zip)
    static func coordsForZip(_ zip: String) -> GeoCoord {
        switch zip.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "30308", "30344": return GeoCoord(latitude: 33.7756, longitude: -84.3963)
        case "30075", "30076": return GeoCoord(latitude: 34.0232, longitude: -84.3615)
        case "30507", "30501": return GeoCoord(latitude: 34.2582, longitude: -83.8185)
        case "30080", "30082": return GeoCoord(latitude: 33.8821, longitude: -84.4811)   // Smyrna
        case "30064", "30060": return GeoCoord(latitude: 33.9407, longitude: -84.5587)   // Marietta
        case "30328":          return GeoCoord(latitude: 33.9379, longitude: -84.3486)   // Sandy Springs
        case "30144", "30152": return GeoCoord(latitude: 34.0234, longitude: -84.6155)   // Kennesaw
        case "30101", "30102": return GeoCoord(latitude: 34.0659, longitude: -84.6769)   // Acworth
        case "30188", "30189": return GeoCoord(latitude: 34.1013, longitude: -84.5194)   // Woodstock
        default:               return GeoCoord(latitude: 33.7490, longitude: -84.3880)   // default GA Atlanta center
        }
    }

    /// The Kotlin default center used as the "needs geocoding" sentinel in the ViewModel.
    static let defaultCenter = GeoCoord(latitude: 33.7490, longitude: -84.3880)

    /// Kotlin: calculateDistanceInMiles(lat1,lon1,lat2,lon2) — spherical law of cosines.
    static func distanceInMiles(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let theta = lon1 - lon2
        var dist = sin(deg2rad(lat1)) * sin(deg2rad(lat2))
                 + cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * cos(deg2rad(theta))
        dist = acos(dist)
        dist = rad2deg(dist)
        dist = dist * 60 * 1.1515
        return dist
    }

    private static func deg2rad(_ deg: Double) -> Double { deg * .pi / 180 }
    private static func rad2deg(_ rad: Double) -> Double { rad * 180 / .pi }
}
