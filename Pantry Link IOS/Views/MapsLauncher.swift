//
//  MapsLauncher.swift
//  Pantry Link IOS
//
//  Opens turn-by-turn directions to a food bank in Apple Maps or Google Maps (with a web
//  fallback if the Google Maps app isn't installed). Used by the Map callout and claim cards.
//

import UIKit
import CoreLocation

enum MapsLauncher {

    /// Apple Maps driving directions to a coordinate (falls back to an address query).
    static func openAppleMaps(name: String, coordinate: CLLocationCoordinate2D?, address: String) {
        let daddr: String
        if let c = coordinate, c.latitude != 0 || c.longitude != 0 {
            daddr = "\(c.latitude),\(c.longitude)"
        } else {
            daddr = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        }
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?daddr=\(daddr)&q=\(q)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }

    /// Google Maps app driving directions; if the app isn't installed, opens Google Maps web.
    static func openGoogleMaps(coordinate: CLLocationCoordinate2D?, address: String) {
        let dest: String
        if let c = coordinate, c.latitude != 0 || c.longitude != 0 {
            dest = "\(c.latitude),\(c.longitude)"
        } else {
            dest = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        }
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
}
