//
//  PantryModels.swift
//  Pantry Link IOS
//
//  Data-layer port of the Android Room entities (com.example.data.Entities.kt).
//  Persistence: SwiftData (@Model) — the iOS 26 native equivalent of Room.
//  Concurrency: @Model objects are isolated to the PantryLinkStore actor. Anything
//  that crosses an actor boundary travels as a Sendable *DTO snapshot* (see below),
//  which is the compile-safe equivalent of handing a Room entity to a coroutine.
//
//  Swift 5.9 / iOS 26.4. No fabricated APIs.
//

import Foundation
import SwiftData

// MARK: - Canonical string values (ported verbatim from the Kotlin status machine)
//
// The Kotlin code compares raw strings ("Posted", "Claimed", …). We keep the exact
// strings for byte-for-byte parity but funnel them through enums so a typo can't
// silently break a status guard.

/// RequestEntity.status lifecycle: Posted → Claimed → Dropped Off → Confirmed by Food Bank → Closed
enum RequestStatus: String {
    case posted             = "Posted"
    case claimed            = "Claimed"
    case droppedOff         = "Dropped Off"
    case confirmedByFoodBank = "Confirmed by Food Bank"
    case closed             = "Closed"
}

/// ClaimEntity.claimStatus lifecycle: Claimed → Ready for Drop-Off → Dropped Off → Accepted / Rejected / Cancelled
enum ClaimStatus: String {
    case claimed          = "Claimed"
    case readyForDropOff  = "Ready for Drop-Off"
    case droppedOff       = "Dropped Off"
    case accepted         = "Accepted"
    case rejected         = "Rejected"
    case cancelled        = "Cancelled"
}

/// AuditLogEntity.actionType values written by the transaction layer.
enum AuditAction: String {
    case claimAccepted        = "CLAIM_ACCEPTED"
    case claimCancelled       = "CLAIM_CANCELLED"
    case claimDroppedOff      = "CLAIM_DROPPED_OFF"
    case claimApproved        = "CLAIM_APPROVED_BY_FOOD_BANK"
    case claimRejected        = "CLAIM_REJECTED_BY_FOOD_BANK"
    case requestClosed        = "REQUEST_CLOSED"
    case claimExpired         = "CLAIM_EXPIRED"
}

/// Approved rejection reasons (Kotlin: ClaimEntity.rejectionReason comment + FBVerifyDropsTab list).
enum RejectionReason: String, CaseIterable {
    case wrongItem          = "wrong item"
    case openedItem         = "opened item"
    case damagedItem        = "damaged item"
    case expiredItem        = "expired item"
    case unsafeItem         = "unsafe item"
    case incompleteQuantity = "incomplete quantity"
}

// MARK: - Result type (Kotlin: sealed class ClaimResult)

enum ClaimResult: Sendable, Equatable {
    case success(claimId: Int)
    case error(message: String)
}

// MARK: - Int-keyed model marker (enables generic auto-increment id allocation)

// `nonisolated`: under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor the protocol and its
// requirements would default to @MainActor, which re-pins the witness property to the main
// actor even on a `nonisolated` model — defeating use inside the store actor.
nonisolated protocol IntIdentified {
    // Named `entityID`, not `id`: keeps our integer primary key distinct from SwiftData's
    // own persistentModelID (which already serves Identifiable on every PersistentModel).
    var entityID: Int { get }
}

// MARK: - SwiftData Models (Room @Entity → SwiftData @Model)

/// Room: food_banks
//
// `nonisolated`: this module compiles with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
// (Xcode 26 Approachable Concurrency). Without this, @Model members default to @MainActor
// and can't be used inside the PantryLinkStore actor. The store serializes all access,
// so opting these value-like persistence models out of main-actor isolation is safe.
@Model
nonisolated final class FoodBank: IntIdentified {
    var entityID: Int   // primary key; uniqueness guaranteed by PantryLinkStore.nextId(_:)
    var name: String
    var address: String
    var zipCode: String
    var city: String
    var state: String
    var latitude: Double
    var longitude: Double
    var phone: String
    var email: String
    var verified: Bool
    var size: String
    var operatingHours: String
    var coldStorage: Bool

    init(
        entityID: Int = 0,
        name: String,
        address: String,
        zipCode: String,
        city: String,
        state: String,
        latitude: Double,
        longitude: Double,
        phone: String,
        email: String,
        verified: Bool = true,
        size: String = "",
        operatingHours: String = "",
        coldStorage: Bool = false
    ) {
        self.entityID = entityID
        self.name = name
        self.address = address
        self.zipCode = zipCode
        self.city = city
        self.state = state
        self.latitude = latitude
        self.longitude = longitude
        self.phone = phone
        self.email = email
        self.verified = verified
        self.size = size
        self.operatingHours = operatingHours
        self.coldStorage = coldStorage
    }
}

/// Room: requests
@Model
nonisolated final class PantryRequest: IntIdentified {
    var entityID: Int   // primary key; uniqueness guaranteed by PantryLinkStore.nextId(_:)
    var foodBankId: Int
    var foodBankName: String
    var title: String
    var category: String            // approved list
    var itemDescription: String     // consistent description format
    var quantityNeeded: Int
    var quantityRemaining: Int
    var deadline: String
    var dropOffLocation: String     // standardized address
    var extraNotes: String
    var status: String              // see RequestStatus

    init(
        entityID: Int = 0,
        foodBankId: Int,
        foodBankName: String,
        title: String,
        category: String,
        itemDescription: String,
        quantityNeeded: Int,
        quantityRemaining: Int,
        deadline: String,
        dropOffLocation: String,
        extraNotes: String,
        status: String
    ) {
        self.entityID = entityID
        self.foodBankId = foodBankId
        self.foodBankName = foodBankName
        self.title = title
        self.category = category
        self.itemDescription = itemDescription
        self.quantityNeeded = quantityNeeded
        self.quantityRemaining = quantityRemaining
        self.deadline = deadline
        self.dropOffLocation = dropOffLocation
        self.extraNotes = extraNotes
        self.status = status
    }
}

/// Room: claims
@Model
nonisolated final class Claim: IntIdentified {
    var entityID: Int   // primary key; uniqueness guaranteed by PantryLinkStore.nextId(_:)
    var requestId: Int
    var requestTitle: String
    var foodBankName: String
    var donorUserId: String
    var quantityClaimed: Int
    var claimTimestamp: Int64
    var claimStatus: String                     // see ClaimStatus
    var dropoffConfirmationTimestamp: Int64?
    var foodBankReviewResult: String?
    var rejectionReason: String?

    init(
        entityID: Int = 0,
        requestId: Int,
        requestTitle: String,
        foodBankName: String,
        donorUserId: String,
        quantityClaimed: Int,
        claimTimestamp: Int64,
        claimStatus: String,
        dropoffConfirmationTimestamp: Int64? = nil,
        foodBankReviewResult: String? = nil,
        rejectionReason: String? = nil
    ) {
        self.entityID = entityID
        self.requestId = requestId
        self.requestTitle = requestTitle
        self.foodBankName = foodBankName
        self.donorUserId = donorUserId
        self.quantityClaimed = quantityClaimed
        self.claimTimestamp = claimTimestamp
        self.claimStatus = claimStatus
        self.dropoffConfirmationTimestamp = dropoffConfirmationTimestamp
        self.foodBankReviewResult = foodBankReviewResult
        self.rejectionReason = rejectionReason
    }
}

/// Room: audit_logs
@Model
nonisolated final class AuditLog: IntIdentified {
    var entityID: Int   // primary key; uniqueness guaranteed by PantryLinkStore.nextId(_:)
    var donorId: String
    var requestId: Int
    var claimId: Int
    var actionType: String
    var timestamp: Int64
    var oldStatus: String
    var newStatus: String

    init(
        entityID: Int = 0,
        donorId: String,
        requestId: Int,
        claimId: Int,
        actionType: String,
        timestamp: Int64,
        oldStatus: String,
        newStatus: String
    ) {
        self.entityID = entityID
        self.donorId = donorId
        self.requestId = requestId
        self.claimId = claimId
        self.actionType = actionType
        self.timestamp = timestamp
        self.oldStatus = oldStatus
        self.newStatus = newStatus
    }
}

// MARK: - Sendable DTO snapshots
//
// @Model instances are reference types bound to the store actor's ModelContext and are
// NOT Sendable. To hand data to the UI / ViewModel / sync layer without a data race we
// copy into these immutable value snapshots — the Swift-concurrency-safe analogue of the
// Kotlin repository passing a data-class entity across a coroutine boundary.

struct FoodBankDTO: Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    let address: String
    let zipCode: String
    let city: String
    let state: String
    let latitude: Double
    let longitude: Double
    let phone: String
    let email: String
    let verified: Bool
    let size: String
    let operatingHours: String
    let coldStorage: Bool
}

struct RequestDTO: Identifiable, Sendable, Hashable {
    let id: Int
    let foodBankId: Int
    let foodBankName: String
    let title: String
    let category: String
    let itemDescription: String
    let quantityNeeded: Int
    let quantityRemaining: Int
    let deadline: String
    let dropOffLocation: String
    let extraNotes: String
    let status: String
}

struct ClaimDTO: Identifiable, Sendable, Hashable {
    let id: Int
    let requestId: Int
    let requestTitle: String
    let foodBankName: String
    let donorUserId: String
    let quantityClaimed: Int
    let claimTimestamp: Int64
    let claimStatus: String
    let dropoffConfirmationTimestamp: Int64?
    let foodBankReviewResult: String?
    let rejectionReason: String?
}

struct AuditLogDTO: Identifiable, Sendable, Hashable {
    let id: Int
    let donorId: String
    let requestId: Int
    let claimId: Int
    let actionType: String
    let timestamp: Int64
    let oldStatus: String
    let newStatus: String
}

// MARK: - @Model → DTO snapshotting

extension FoodBank {
    var dto: FoodBankDTO {
        FoodBankDTO(id: entityID, name: name, address: address, zipCode: zipCode, city: city,
                    state: state, latitude: latitude, longitude: longitude, phone: phone,
                    email: email, verified: verified, size: size,
                    operatingHours: operatingHours, coldStorage: coldStorage)
    }
}

extension PantryRequest {
    var dto: RequestDTO {
        RequestDTO(id: entityID, foodBankId: foodBankId, foodBankName: foodBankName, title: title,
                   category: category, itemDescription: itemDescription,
                   quantityNeeded: quantityNeeded, quantityRemaining: quantityRemaining,
                   deadline: deadline, dropOffLocation: dropOffLocation,
                   extraNotes: extraNotes, status: status)
    }
}

extension Claim {
    var dto: ClaimDTO {
        ClaimDTO(id: entityID, requestId: requestId, requestTitle: requestTitle,
                 foodBankName: foodBankName, donorUserId: donorUserId,
                 quantityClaimed: quantityClaimed, claimTimestamp: claimTimestamp,
                 claimStatus: claimStatus,
                 dropoffConfirmationTimestamp: dropoffConfirmationTimestamp,
                 foodBankReviewResult: foodBankReviewResult, rejectionReason: rejectionReason)
    }
}

extension AuditLog {
    var dto: AuditLogDTO {
        AuditLogDTO(id: entityID, donorId: donorId, requestId: requestId, claimId: claimId,
                    actionType: actionType, timestamp: timestamp,
                    oldStatus: oldStatus, newStatus: newStatus)
    }
}
