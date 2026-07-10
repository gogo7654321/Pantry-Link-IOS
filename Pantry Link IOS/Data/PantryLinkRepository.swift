//
//  PantryLinkRepository.swift
//  Pantry Link IOS
//
//  Port of com.example.data.PantryLinkRepository.kt.
//  Same responsibility: run a store transaction, and on success push the affected
//  entities to the sync layer. The Android version returns Kotlin Flows; on iOS the
//  live/reactive reads are served by SwiftData's @Query in the view layer, so here we
//  expose async snapshot reads plus the write/transaction wrappers.
//
//  Swift 5.9 / iOS 26.4.
//

import Foundation

final class PantryLinkRepository: Sendable {

    private let store: PantryLinkStore
    private let sync: PantrySyncManager

    init(store: PantryLinkStore, sync: PantrySyncManager = NoOpSyncManager()) {
        self.store = store
        self.sync = sync
    }

    // MARK: - Snapshot reads (Kotlin exposed these as Flows)

    func allFoodBanks() async throws -> [FoodBankDTO] { try await store.allFoodBanks() }
    func allRequests() async throws -> [RequestDTO]   { try await store.allRequests() }
    func allClaims() async throws -> [ClaimDTO]       { try await store.allClaims() }
    func allAuditLogs() async throws -> [AuditLogDTO] { try await store.allAuditLogs() }

    func claims(forDonor donorId: String) async throws -> [ClaimDTO] {
        try await store.claims(forDonor: donorId)
    }

    func request(id: Int) async throws -> RequestDTO? { try await store.request(id: id) }
    func claim(id: Int) async throws -> ClaimDTO?     { try await store.claim(id: id) }

    // MARK: - Requests

    @discardableResult
    func insertRequest(_ request: RequestDTO) async throws -> Int {
        let id = try await store.insertRequest(request)
        if let created = try await store.request(id: id) {
            await sync.pushRequest(created)
        }
        return id
    }

    func updateRequest(_ request: RequestDTO) async throws {
        try await store.updateRequest(request)
        await sync.pushRequest(request)
    }

    func deleteRequest(id: Int) async throws {
        try await store.deleteRequest(id: id)
        await sync.deleteRequestOnRemote(id: id)
    }

    // MARK: - Transactions (each pushes affected entities on success, exactly like Kotlin)

    func tryClaimRequest(
        donorId: String,
        requestId: Int,
        quantityToClaim: Int,
        timestamp: Int64
    ) async throws -> ClaimResult {
        let result = try await store.claimRequestTransaction(
            donorId: donorId,
            requestId: requestId,
            quantityToClaim: quantityToClaim,
            timestamp: timestamp
        )
        if case let .success(claimId) = result {
            if let updatedRequest = try await store.request(id: requestId) {
                await sync.pushRequest(updatedRequest)
            }
            if let createdClaim = try await store.claim(id: claimId) {
                await sync.pushClaim(createdClaim)
            }
            await pushAuditLogs(since: timestamp)
        }
        return result
    }

    func tryCancelClaim(claimId: Int, donorId: String, timestamp: Int64) async throws -> Bool {
        let success = try await store.cancelClaimTransaction(
            claimId: claimId, donorId: donorId, timestamp: timestamp
        )
        if success { try await pushClaimAndRequest(claimId: claimId); await pushAuditLogs(since: timestamp) }
        return success
    }

    func markClaimAsDroppedOff(claimId: Int, timestamp: Int64) async throws -> Bool {
        let success = try await store.dropOffClaimTransaction(claimId: claimId, timestamp: timestamp)
        if success { try await pushClaimAndRequest(claimId: claimId); await pushAuditLogs(since: timestamp) }
        return success
    }

    func reviewClaim(
        claimId: Int,
        approved: Bool,
        rejectionReason: String?,
        timestamp: Int64
    ) async throws -> Bool {
        let success = try await store.reviewClaimTransaction(
            claimId: claimId, approved: approved, rejectionReason: rejectionReason, timestamp: timestamp
        )
        if success { try await pushClaimAndRequest(claimId: claimId); await pushAuditLogs(since: timestamp) }
        return success
    }

    func closeRequest(requestId: Int, timestamp: Int64) async throws -> Bool {
        let success = try await store.closeRequestTransaction(requestId: requestId, timestamp: timestamp)
        if success, let updated = try await store.request(id: requestId) {
            await sync.pushRequest(updated)
        }
        if success { await pushAuditLogs(since: timestamp) }
        return success
    }

    func expireClaim(claimId: Int, timestamp: Int64) async throws -> Bool {
        let success = try await store.expireClaimTransaction(claimId: claimId, timestamp: timestamp)
        if success { try await pushClaimAndRequest(claimId: claimId); await pushAuditLogs(since: timestamp) }
        return success
    }

    // MARK: - Food Banks

    @discardableResult
    func insertFoodBank(_ foodBank: FoodBankDTO) async throws -> Int {
        let id = try await store.insertFoodBank(foodBank)
        if let created = try await store.foodBank(id: id) {
            await sync.pushFoodBank(created)
        }
        return id
    }

    func deleteFoodBank(email: String) async throws {
        try await store.deleteFoodBank(email: email)
    }

    // MARK: - Helpers

    /// Kotlin pattern: after a claim mutation, push the claim then its parent request.
    private func pushClaimAndRequest(claimId: Int) async throws {
        guard let claim = try await store.claim(id: claimId) else { return }
        await sync.pushClaim(claim)
        if let request = try await store.request(id: claim.requestId) {
            await sync.pushRequest(request)
        }
    }

    /// Push the audit-log entries created by a transaction (those stamped at/after its timestamp)
    /// up to Firestore, so the audit trail is visible across devices and to the food bank.
    private func pushAuditLogs(since timestamp: Int64) async {
        let logs = (try? await store.allAuditLogs()) ?? []
        for log in logs where log.timestamp >= timestamp {
            await sync.pushAuditLog(log)
        }
    }
}
