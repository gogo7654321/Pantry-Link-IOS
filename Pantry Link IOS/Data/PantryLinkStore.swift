//
//  PantryLinkStore.swift
//  Pantry Link IOS
//
//  Port of com.example.data.PantryLinkDao.kt.
//  Each Kotlin @Transaction becomes an `async` method on this @ModelActor. SwiftData's
//  ModelContext is single-writer and isolated to this actor, giving us the same
//  serialized, atomic semantics Room's @Transaction provided. Every guard clause,
//  quantity calculation, status transition and audit-log write is a line-for-line copy
//  of the Kotlin source — only the syntax changed.
//
//  Swift 5.9 / iOS 26.4.
//

import Foundation
import SwiftData

@ModelActor
actor PantryLinkStore {

    // MARK: - Auto-increment id allocation
    //
    // Room's @PrimaryKey(autoGenerate = true) hands out increasing rowids. SwiftData has
    // no autoincrement, so we emulate it: next id = (current max id) + 1. Because every
    // mutation runs on this actor, the read-then-write is race-free.

    private func nextId<T: PersistentModel & IntIdentified>(_ type: T.Type) throws -> Int {
        var descriptor = FetchDescriptor<T>(sortBy: [SortDescriptor(\.entityID, order: .reverse)])
        descriptor.fetchLimit = 1
        let maxId = try modelContext.fetch(descriptor).first?.entityID ?? 0
        return maxId + 1
    }

    private func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    // MARK: - Internal @Model fetch helpers (actor-local; never leave the actor)

    private func requestModel(_ id: Int) throws -> PantryRequest? {
        var d = FetchDescriptor<PantryRequest>(predicate: #Predicate { $0.entityID == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func claimModel(_ id: Int) throws -> Claim? {
        var d = FetchDescriptor<Claim>(predicate: #Predicate { $0.entityID == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func foodBankModel(_ id: Int) throws -> FoodBank? {
        var d = FetchDescriptor<FoodBank>(predicate: #Predicate { $0.entityID == id })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }

    private func claimModels(forRequest requestId: Int) throws -> [Claim] {
        let d = FetchDescriptor<Claim>(predicate: #Predicate { $0.requestId == requestId })
        return try modelContext.fetch(d)
    }

    // =====================================================================================
    // MARK: - Food Banks
    // =====================================================================================

    /// Kotlin: getAllFoodBanks() — ORDER BY name ASC
    func allFoodBanks() throws -> [FoodBankDTO] {
        let d = FetchDescriptor<FoodBank>(sortBy: [SortDescriptor(\.name, order: .forward)])
        return try modelContext.fetch(d).map(\.dto)
    }

    /// Kotlin: getFoodBankById(id)
    func foodBank(id: Int) throws -> FoodBankDTO? {
        try foodBankModel(id)?.dto
    }

    /// Kotlin: insertFoodBank(foodBank) — onConflict = REPLACE, returns row id
    @discardableResult
    func insertFoodBank(_ input: FoodBankDTO) throws -> Int {
        // REPLACE semantics: if an id was supplied and already exists, overwrite in place.
        if input.id != 0, let existing = try foodBankModel(input.id) {
            existing.name = input.name
            existing.address = input.address
            existing.zipCode = input.zipCode
            existing.city = input.city
            existing.state = input.state
            existing.latitude = input.latitude
            existing.longitude = input.longitude
            existing.phone = input.phone
            existing.email = input.email
            existing.verified = input.verified
            existing.size = input.size
            existing.operatingHours = input.operatingHours
            existing.coldStorage = input.coldStorage
            try save()
            return existing.entityID
        }

        let newId = input.id != 0 ? input.id : try nextId(FoodBank.self)
        let model = FoodBank(
            entityID: newId, name: input.name, address: input.address, zipCode: input.zipCode,
            city: input.city, state: input.state, latitude: input.latitude,
            longitude: input.longitude, phone: input.phone, email: input.email,
            verified: input.verified, size: input.size,
            operatingHours: input.operatingHours, coldStorage: input.coldStorage
        )
        modelContext.insert(model)
        try save()
        return newId
    }

    /// Kotlin: deleteFoodBankByEmail(email)
    func deleteFoodBank(email: String) throws {
        let d = FetchDescriptor<FoodBank>(predicate: #Predicate { $0.email == email })
        for bank in try modelContext.fetch(d) {
            modelContext.delete(bank)
        }
        try save()
    }

    // =====================================================================================
    // MARK: - Requests
    // =====================================================================================

    /// Kotlin: getAllRequests() — ORDER BY id DESC
    func allRequests() throws -> [RequestDTO] {
        let d = FetchDescriptor<PantryRequest>(sortBy: [SortDescriptor(\.entityID, order: .reverse)])
        return try modelContext.fetch(d).map(\.dto)
    }

    /// Kotlin: getRequestById(id)
    func request(id: Int) throws -> RequestDTO? {
        try requestModel(id)?.dto
    }

    /// Kotlin: insertRequest(request) — onConflict = REPLACE, returns row id
    @discardableResult
    func insertRequest(_ input: RequestDTO) throws -> Int {
        if input.id != 0, let existing = try requestModel(input.id) {
            existing.foodBankId = input.foodBankId
            existing.foodBankName = input.foodBankName
            existing.title = input.title
            existing.category = input.category
            existing.itemDescription = input.itemDescription
            existing.quantityNeeded = input.quantityNeeded
            existing.quantityRemaining = input.quantityRemaining
            existing.deadline = input.deadline
            existing.dropOffLocation = input.dropOffLocation
            existing.extraNotes = input.extraNotes
            existing.status = input.status
            try save()
            return existing.entityID
        }

        let newId = input.id != 0 ? input.id : try nextId(PantryRequest.self)
        let model = PantryRequest(
            entityID: newId, foodBankId: input.foodBankId, foodBankName: input.foodBankName,
            title: input.title, category: input.category, itemDescription: input.itemDescription,
            quantityNeeded: input.quantityNeeded, quantityRemaining: input.quantityRemaining,
            deadline: input.deadline, dropOffLocation: input.dropOffLocation,
            extraNotes: input.extraNotes, status: input.status
        )
        modelContext.insert(model)
        try save()
        return newId
    }

    /// Kotlin: updateRequest(request)
    func updateRequest(_ input: RequestDTO) throws {
        guard let existing = try requestModel(input.id) else { return }
        existing.foodBankId = input.foodBankId
        existing.foodBankName = input.foodBankName
        existing.title = input.title
        existing.category = input.category
        existing.itemDescription = input.itemDescription
        existing.quantityNeeded = input.quantityNeeded
        existing.quantityRemaining = input.quantityRemaining
        existing.deadline = input.deadline
        existing.dropOffLocation = input.dropOffLocation
        existing.extraNotes = input.extraNotes
        existing.status = input.status
        try save()
    }

    /// Kotlin: deleteRequest(request)
    func deleteRequest(id: Int) throws {
        if let existing = try requestModel(id) {
            modelContext.delete(existing)
            try save()
        }
    }

    // =====================================================================================
    // MARK: - Claims
    // =====================================================================================

    /// Kotlin: getAllClaimsDirect() — ORDER BY claimTimestamp DESC
    func allClaims() throws -> [ClaimDTO] {
        let d = FetchDescriptor<Claim>(sortBy: [SortDescriptor(\.claimTimestamp, order: .reverse)])
        return try modelContext.fetch(d).map(\.dto)
    }

    /// Kotlin: getClaimsForDonor(donorId) — WHERE donorUserId = :donorId ORDER BY claimTimestamp DESC
    func claims(forDonor donorId: String) throws -> [ClaimDTO] {
        let d = FetchDescriptor<Claim>(
            predicate: #Predicate { $0.donorUserId == donorId },
            sortBy: [SortDescriptor(\.claimTimestamp, order: .reverse)]
        )
        return try modelContext.fetch(d).map(\.dto)
    }

    /// Kotlin: getClaimsForRequest(requestId)
    func claims(forRequest requestId: Int) throws -> [ClaimDTO] {
        try claimModels(forRequest: requestId).map(\.dto)
    }

    /// Kotlin: getClaimById(claimId)
    func claim(id: Int) throws -> ClaimDTO? {
        try claimModel(id)?.dto
    }

    /// Upsert a claim by id (REPLACE), used by the Firestore listener to mirror remote
    /// state locally without going back through the push path (avoids sync loops).
    /// Mirrors Kotlin dao.insertClaim(onConflict = REPLACE).
    @discardableResult
    func upsertClaim(_ input: ClaimDTO) throws -> Int {
        if input.id != 0, let existing = try claimModel(input.id) {
            existing.requestId = input.requestId
            existing.requestTitle = input.requestTitle
            existing.foodBankName = input.foodBankName
            existing.donorUserId = input.donorUserId
            existing.quantityClaimed = input.quantityClaimed
            existing.claimTimestamp = input.claimTimestamp
            existing.claimStatus = input.claimStatus
            existing.dropoffConfirmationTimestamp = input.dropoffConfirmationTimestamp
            existing.foodBankReviewResult = input.foodBankReviewResult
            existing.rejectionReason = input.rejectionReason
            try save()
            return existing.entityID
        }
        let newId = input.id != 0 ? input.id : try nextId(Claim.self)
        let model = Claim(
            entityID: newId, requestId: input.requestId, requestTitle: input.requestTitle,
            foodBankName: input.foodBankName, donorUserId: input.donorUserId,
            quantityClaimed: input.quantityClaimed, claimTimestamp: input.claimTimestamp,
            claimStatus: input.claimStatus,
            dropoffConfirmationTimestamp: input.dropoffConfirmationTimestamp,
            foodBankReviewResult: input.foodBankReviewResult, rejectionReason: input.rejectionReason
        )
        modelContext.insert(model)
        try save()
        return newId
    }

    // =====================================================================================
    // MARK: - Audit Logs
    // =====================================================================================

    /// Kotlin: getAllAuditLogs() — ORDER BY timestamp DESC
    func allAuditLogs() throws -> [AuditLogDTO] {
        let d = FetchDescriptor<AuditLog>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try modelContext.fetch(d).map(\.dto)
    }

    /// Insert-or-update an audit log by id (used by the Firestore listener so the trail syncs
    /// across devices/users, not just the device that created it).
    @discardableResult
    func upsertAuditLog(_ input: AuditLogDTO) throws -> Int {
        let target = input.id
        if target != 0 {
            var d = FetchDescriptor<AuditLog>(predicate: #Predicate { $0.entityID == target })
            d.fetchLimit = 1
            if let existing = try modelContext.fetch(d).first {
                existing.donorId = input.donorId
                existing.requestId = input.requestId
                existing.claimId = input.claimId
                existing.actionType = input.actionType
                existing.timestamp = input.timestamp
                existing.oldStatus = input.oldStatus
                existing.newStatus = input.newStatus
                try save()
                return existing.entityID
            }
        }
        let newId = target != 0 ? target : try nextId(AuditLog.self)
        let model = AuditLog(
            entityID: newId, donorId: input.donorId, requestId: input.requestId,
            claimId: input.claimId, actionType: input.actionType, timestamp: input.timestamp,
            oldStatus: input.oldStatus, newStatus: input.newStatus
        )
        modelContext.insert(model)
        try save()
        return newId
    }

    /// Internal: append an audit log (Kotlin: insertAuditLog). Runs inside a transaction.
    @discardableResult
    private func appendAuditLog(
        donorId: String,
        requestId: Int,
        claimId: Int,
        actionType: AuditAction,
        timestamp: Int64,
        oldStatus: String,
        newStatus: String
    ) throws -> Int {
        let newId = try nextId(AuditLog.self)
        let log = AuditLog(
            entityID: newId, donorId: donorId, requestId: requestId, claimId: claimId,
            actionType: actionType.rawValue, timestamp: timestamp,
            oldStatus: oldStatus, newStatus: newStatus
        )
        modelContext.insert(log)
        return newId
    }

    // =====================================================================================
    // MARK: - Transaction-safe operations (the "backend" simulation)
    //         1:1 port of the Kotlin @Transaction functions.
    // =====================================================================================

    /// Kotlin: claimRequestTransaction(donorId, requestId, quantityToClaim, timestamp)
    func claimRequestTransaction(
        donorId: String,
        requestId: Int,
        quantityToClaim: Int,
        timestamp: Int64
    ) throws -> ClaimResult {
        guard let request = try requestModel(requestId) else {
            return .error(message: "Request not found.")
        }

        // A. Verify request is open (status is not Closed/Confirmed by Food Bank)
        if request.status == RequestStatus.closed.rawValue
            || request.status == RequestStatus.confirmedByFoodBank.rawValue {
            return .error(message: "Acceptance blocked: This request is already concluded or closed.")
        }

        // B. Verify quantity is available & greater than remaining
        if request.quantityRemaining <= 0 {
            return .error(message: "Acceptance blocked: This item request is already fully claimed.")
        }

        if quantityToClaim <= 0 {
            return .error(message: "Quantity to claim must be greater than zero.")
        }

        if quantityToClaim > request.quantityRemaining {
            return .error(message: "Acceptance blocked: Only \(request.quantityRemaining) items remaining, cannot claim \(quantityToClaim).")
        }

        // Capture the pre-update status for the audit log (Kotlin reads the original `request`).
        let originalStatus = request.status

        // C. Update the request
        let newRemaining = request.quantityRemaining - quantityToClaim
        // If items still remain, keep "Posted" so more neighbors can claim. Otherwise "Claimed".
        let newRequestStatus = newRemaining <= 0 ? RequestStatus.claimed.rawValue : RequestStatus.posted.rawValue
        request.quantityRemaining = newRemaining
        request.status = newRequestStatus

        // D. Create the Claim Entity
        let claimId = try nextId(Claim.self)
        let claim = Claim(
            entityID: claimId,
            requestId: requestId,
            requestTitle: request.title,
            foodBankName: request.foodBankName,
            donorUserId: donorId,
            quantityClaimed: quantityToClaim,
            claimTimestamp: timestamp,
            claimStatus: ClaimStatus.claimed.rawValue
        )
        modelContext.insert(claim)

        // E. Log the action
        try appendAuditLog(
            donorId: donorId,
            requestId: requestId,
            claimId: claimId,
            actionType: .claimAccepted,
            timestamp: timestamp,
            oldStatus: originalStatus,
            newStatus: RequestStatus.claimed.rawValue
        )

        try save()
        return .success(claimId: claimId)
    }

    /// Kotlin: cancelClaimTransaction(claimId, donorId, timestamp)
    func cancelClaimTransaction(claimId: Int, donorId: String, timestamp: Int64) throws -> Bool {
        guard let claim = try claimModel(claimId) else { return false }
        if claim.donorUserId != donorId { return false }

        // Block if already dropped off
        if claim.claimStatus == ClaimStatus.droppedOff.rawValue
            || claim.claimStatus == ClaimStatus.accepted.rawValue {
            return false
        }

        let oldClaimStatus = claim.claimStatus   // for the audit log

        // 1. Mark claim as Cancelled
        claim.claimStatus = ClaimStatus.cancelled.rawValue

        // 2. Restore quantity
        if let request = try requestModel(claim.requestId) {
            let restoredRemaining = request.quantityRemaining + claim.quantityClaimed
            // If restored quantity > 0, status goes back to "Posted".
            let restoredStatus = restoredRemaining > 0 ? RequestStatus.posted.rawValue : request.status
            request.quantityRemaining = min(restoredRemaining, request.quantityNeeded)  // coerceAtMost
            request.status = restoredStatus
        }

        // 3. Log
        try appendAuditLog(
            donorId: donorId,
            requestId: claim.requestId,
            claimId: claimId,
            actionType: .claimCancelled,
            timestamp: timestamp,
            oldStatus: oldClaimStatus,
            newStatus: ClaimStatus.cancelled.rawValue
        )

        try save()
        return true
    }

    /// Kotlin: dropOffClaimTransaction(claimId, timestamp)
    func dropOffClaimTransaction(claimId: Int, timestamp: Int64) throws -> Bool {
        guard let claim = try claimModel(claimId) else { return false }
        if claim.claimStatus != ClaimStatus.claimed.rawValue
            && claim.claimStatus != ClaimStatus.readyForDropOff.rawValue {
            return false
        }

        let oldClaimStatus = claim.claimStatus

        // Update claim to "Dropped Off"
        claim.claimStatus = ClaimStatus.droppedOff.rawValue
        claim.dropoffConfirmationTimestamp = timestamp

        // Update main request status
        if let request = try requestModel(claim.requestId) {
            // Main request transitions to "Dropped Off" only if there is nothing left to claim.
            // Otherwise keep "Posted" so others can fulfill what is still needed.
            let newRequestStatus = request.quantityRemaining <= 0
                ? RequestStatus.droppedOff.rawValue
                : RequestStatus.posted.rawValue
            request.status = newRequestStatus
        }

        // Log
        try appendAuditLog(
            donorId: claim.donorUserId,
            requestId: claim.requestId,
            claimId: claimId,
            actionType: .claimDroppedOff,
            timestamp: timestamp,
            oldStatus: oldClaimStatus,
            newStatus: ClaimStatus.droppedOff.rawValue
        )

        try save()
        return true
    }

    /// Kotlin: reviewClaimTransaction(claimId, approved, rejectionReason, timestamp)
    func reviewClaimTransaction(
        claimId: Int,
        approved: Bool,
        rejectionReason: String?,
        timestamp: Int64
    ) throws -> Bool {
        guard let claim = try claimModel(claimId) else { return false }
        if claim.claimStatus != ClaimStatus.droppedOff.rawValue { return false }

        if approved {
            // A. Move donor claim to Accepted
            claim.claimStatus = ClaimStatus.accepted.rawValue
            claim.foodBankReviewResult = ClaimStatus.accepted.rawValue

            if let request = try requestModel(claim.requestId) {
                // Compute total accepted quantity across all claims for this request.
                // (Kotlin folds the just-updated claim in via its id, others only if Accepted.)
                let requestClaims = try claimModels(forRequest: claim.requestId)
                var totalAccepted = 0
                for element in requestClaims {
                    if element.entityID == claimId {
                        totalAccepted += claim.quantityClaimed
                    } else if element.claimStatus == ClaimStatus.accepted.rawValue {
                        totalAccepted += element.quantityClaimed
                    }
                }

                let fullySatisfied = totalAccepted >= request.quantityNeeded || request.quantityRemaining <= 0
                let newRequestStatus: String
                if fullySatisfied {
                    newRequestStatus = RequestStatus.confirmedByFoodBank.rawValue
                } else {
                    newRequestStatus = request.quantityRemaining > 0
                        ? RequestStatus.posted.rawValue
                        : RequestStatus.droppedOff.rawValue
                }
                request.status = newRequestStatus
            }

            try appendAuditLog(
                donorId: claim.donorUserId,
                requestId: claim.requestId,
                claimId: claimId,
                actionType: .claimApproved,
                timestamp: timestamp,
                oldStatus: ClaimStatus.droppedOff.rawValue,
                newStatus: ClaimStatus.accepted.rawValue
            )

        } else {
            // B. Move donor claim to Rejected
            claim.claimStatus = ClaimStatus.rejected.rawValue
            claim.foodBankReviewResult = ClaimStatus.rejected.rawValue
            claim.rejectionReason = rejectionReason

            // Restore quantity back into request
            if let request = try requestModel(claim.requestId) {
                let restoredRemaining = request.quantityRemaining + claim.quantityClaimed
                let restoredStatus = restoredRemaining > 0
                    ? RequestStatus.posted.rawValue
                    : RequestStatus.claimed.rawValue
                request.quantityRemaining = min(restoredRemaining, request.quantityNeeded)
                request.status = restoredStatus
            }

            try appendAuditLog(
                donorId: claim.donorUserId,
                requestId: claim.requestId,
                claimId: claimId,
                actionType: .claimRejected,
                timestamp: timestamp,
                oldStatus: ClaimStatus.droppedOff.rawValue,
                newStatus: ClaimStatus.rejected.rawValue
            )
        }

        try save()
        return true
    }

    /// Kotlin: closeRequestTransaction(requestId, timestamp)
    func closeRequestTransaction(requestId: Int, timestamp: Int64) throws -> Bool {
        guard let request = try requestModel(requestId) else { return false }
        let originalStatus = request.status
        request.status = RequestStatus.closed.rawValue

        try appendAuditLog(
            donorId: "SYSTEM_FOOD_BANK",
            requestId: requestId,
            claimId: 0,
            actionType: .requestClosed,
            timestamp: timestamp,
            oldStatus: originalStatus,
            newStatus: RequestStatus.closed.rawValue
        )

        try save()
        return true
    }

    /// Kotlin: expireClaimTransaction(claimId, timestamp)
    func expireClaimTransaction(claimId: Int, timestamp: Int64) throws -> Bool {
        guard let claim = try claimModel(claimId) else { return false }
        if claim.claimStatus != ClaimStatus.claimed.rawValue
            && claim.claimStatus != ClaimStatus.readyForDropOff.rawValue {
            return false
        }

        let oldClaimStatus = claim.claimStatus

        // Set status to Cancelled / Expired
        claim.claimStatus = ClaimStatus.cancelled.rawValue
        claim.rejectionReason = "Claim expired (time limit elapsed)"

        // Restore quantity
        if let request = try requestModel(claim.requestId) {
            let restoredRemaining = request.quantityRemaining + claim.quantityClaimed
            let restoredStatus = restoredRemaining > 0 ? RequestStatus.posted.rawValue : request.status
            request.quantityRemaining = min(restoredRemaining, request.quantityNeeded)
            request.status = restoredStatus
        }

        // Log
        try appendAuditLog(
            donorId: claim.donorUserId,
            requestId: claim.requestId,
            claimId: claimId,
            actionType: .claimExpired,
            timestamp: timestamp,
            oldStatus: oldClaimStatus,
            newStatus: ClaimStatus.cancelled.rawValue
        )

        try save()
        return true
    }
}
