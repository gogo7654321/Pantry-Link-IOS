//
//  PantrySupportTypes.swift
//  Pantry Link IOS
//
//  ViewModel-tier value types ported from PantryLinkViewModel.kt (PantryUserSession,
//  DiagnosticItem, SavedLocation) plus the loose Firestore profile map, which we model
//  as a typed Codable `UserProfile` (same fields, safer Swift). Also the constant option
//  lists the Android UI reads (roles, categories, capacities, …).
//

import Foundation

// MARK: - Session (Kotlin: data class PantryUserSession)

struct PantryUserSession: Codable, Sendable, Equatable {
    var email: String
    var uid: String
    var isDemo: Bool = false
}

// MARK: - User profile (Kotlin stored this as a loose Map<String, Any> in Firestore/prefs)

struct UserProfile: Codable, Sendable, Equatable {
    var email: String = ""
    var role: String = "Donor"
    var name: String = ""
    var phone: String = ""
    var isDemo: Bool = false
    var createdAt: Int64 = 0

    // Donor fields
    var donorZip: String = ""
    var donorCity: String = ""
    var donorCanServeType: String = ""
    var donorCanServeQty: String = ""
    var donorFrequency: String = ""

    // Food Bank fields
    var fbAddress: String = ""
    var fbCity: String = ""
    var fbZip: String = ""
    var fbSize: String = ""
    var fbHours: String = ""
    var fbColdStorage: Bool = false
}

// MARK: - Diagnostics (Kotlin: data class DiagnosticItem)

enum DiagnosticStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case success = "SUCCESS"
    case failure = "FAILURE"
}

struct DiagnosticItem: Identifiable, Sendable, Equatable {
    var name: String
    var status: DiagnosticStatus
    var message: String
    var id: String { name }
}

// MARK: - Saved locations (Kotlin: data class SavedLocation)

struct SavedLocation: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let address: String
    let zipCode: String
    var notes: String = ""
    // Exact coordinates captured from address autocomplete (MKLocalSearch). When present these are
    // used verbatim; otherwise we fall back to the LocationHelper ZIP approximation.
    var latitude: Double? = nil
    var longitude: Double? = nil

    /// The coordinate to pin on the map: precise geocoded value when available, else the approximation.
    var coordinate: GeoCoord {
        if let latitude, let longitude { return GeoCoord(latitude: latitude, longitude: longitude) }
        return LocationHelper.coords(address: address, zip: zipCode)
    }
}

// MARK: - Roles

enum PantryRole: String, CaseIterable, Sendable {
    case donor = "Donor"
    case foodBank = "Food Bank"
}

// MARK: - Option lists surfaced in the Android UI (kept verbatim for parity)

enum PantryConstants {
    static let roles = ["Donor", "Food Bank"]

    /// DonorBrowseRequestsTab filter chips (includes "All").
    static let browseCategories = ["All", "Canned Foods", "Hygiene Products", "Baby Supplies", "School Supplies", "Shelf-Stable Items"]

    /// FBPostRequestTab category options (no "All").
    static let requestCategories = ["Canned Foods", "Hygiene Products", "Baby Supplies", "School Supplies", "Shelf-Stable Items"]

    static let donorFoodTypes = ["Fresh Produce", "Canned Goods", "Dry Goods", "Dairy", "Prepared Food"]
    static let donorFoodTypesWithAll = ["Fresh Produce", "Canned Goods", "Dry Goods", "Dairy", "Prepared Food", "All Categories"]
    static let donorCapacities = ["Single bag / box", "Trunk Load", "Full SUV / Van", "Pallets / Large Truck"]
    static let frequencies = ["Weekly", "Bi-weekly", "Monthly", "Occasionally"]

    static let foodBankSizes = ["Small (<100/wk)", "Medium (100-500/wk)", "Large (500+/wk)"]
    static let operatingDays = ["Mon-Fri", "Mon-Sat", "Weekends", "Daily", "By Appt Only"]
    static let operatingHoursPresets = ["9 AM - 5 PM", "8 AM - 12 PM", "12 PM - 6 PM", "Custom Hours"]

    static let rejectionReasons = RejectionReason.allCases.map(\.rawValue)

    static let defaultZip = "30308"          // Midtown Atlanta
    static let defaultMaxDistanceMiles = 25.0
}
