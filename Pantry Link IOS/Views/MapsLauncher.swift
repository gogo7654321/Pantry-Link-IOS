//
//  MapsLauncher.swift
//  Pantry Link IOS
//
//  Opens turn-by-turn directions in Apple Maps or Google Maps using the destination's ADDRESS
//  (not a stored coordinate). Apple/Google geocode the address themselves, which is far more
//  reliable than any coordinate we hold — so directions always point at the real place.
//

import UIKit

enum MapsLauncher {

    /// Apple Maps driving directions to an address.
    static func openAppleMaps(name: String, address: String) {
        let daddr = encode(address)
        let component = daddr.isEmpty ? "q=\(encode(name))" : "daddr=\(daddr)&dirflg=d"
        if let url = URL(string: "http://maps.apple.com/?\(component)") {
            UIApplication.shared.open(url)
        }
    }

    /// Google Maps app driving directions; falls back to Google Maps web if the app isn't installed.
    static func openGoogleMaps(address: String) {
        let dest = encode(address)
        guard !dest.isEmpty else { return }
        let appURL = URL(string: "comgooglemaps://?daddr=\(dest)&directionsmode=driving")
        let webURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(dest)&travelmode=driving")
        if let appURL {
            UIApplication.shared.open(appURL, options: [:]) { opened in
                if !opened, let webURL { UIApplication.shared.open(webURL) }
            }
        } else if let webURL {
            UIApplication.shared.open(webURL)
        }
    }

    private static func encode(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
}
