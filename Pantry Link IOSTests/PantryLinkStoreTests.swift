//
//  PantryLinkStoreTests.swift
//  Pantry Link IOSTests
//
//  Behavioral parity tests: assert the ported SwiftData transactions reproduce the exact
//  status-machine rules of the Android Room DAO (com.example.data.PantryLinkDao.kt).
//

import Testing
import SwiftData
@testable import Pantry_Link_IOS

@Suite("PantryLinkStore transaction parity")
struct PantryLinkStoreTests {

    /// Fresh in-memory store per test.
    private func makeStore() -> PantryLinkStore {
        let container = PantryPersistence.makeContainer(inMemory: true)
        return PantryLinkStore(modelContainer: container)
    }

    private func seedRequest(_ store: PantryLinkStore, needed: Int) async throws -> Int {
        let dto = RequestDTO(
            id: 0, foodBankId: 1, foodBankName: "Test Bank", title: "Canned Beans",
            category: "Canned Foods", itemDescription: "Standard cans", quantityNeeded: needed,
            quantityRemaining: needed, deadline: "2026-12-31", dropOffLocation: "123 Peachtree",
            extraNotes: "", status: RequestStatus.posted.rawValue
        )
        return try await store.insertRequest(dto)
    }

    // MARK: - claimRequestTransaction

    @Test("Partial claim keeps request Posted and decrements remaining")
    func partialClaim() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 5)

        let result = try await store.claimRequestTransaction(
            donorId: "donor@x.com", requestId: reqId, quantityToClaim: 2, timestamp: 1000)

        guard case let .success(claimId) = result else {
            Issue.record("expected success, got \(result)"); return
        }
        let req = try await store.request(id: reqId)
        #expect(req?.quantityRemaining == 3)
        #expect(req?.status == RequestStatus.posted.rawValue)   // still Posted: items remain

        let claim = try await store.claim(id: claimId)
        #expect(claim?.claimStatus == ClaimStatus.claimed.rawValue)
        #expect(claim?.quantityClaimed == 2)

        let logs = try await store.allAuditLogs()
        #expect(logs.contains { $0.actionType == AuditAction.claimAccepted.rawValue })
    }

    @Test("Full claim flips request to Claimed")
    func fullClaim() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 5)
        _ = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 5, timestamp: 1000)
        let req = try await store.request(id: reqId)
        #expect(req?.quantityRemaining == 0)
        #expect(req?.status == RequestStatus.claimed.rawValue)
    }

    @Test("Over-claim is blocked with exact Kotlin message")
    func overClaim() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 5)
        let result = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 6, timestamp: 1000)
        #expect(result == .error(message: "Acceptance blocked: Only 5 items remaining, cannot claim 6."))
    }

    @Test("Zero quantity is rejected")
    func zeroClaim() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 5)
        let result = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 0, timestamp: 1000)
        #expect(result == .error(message: "Quantity to claim must be greater than zero."))
    }

    @Test("Claiming a closed request is blocked")
    func claimClosed() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 5)
        _ = try await store.closeRequestTransaction(requestId: reqId, timestamp: 500)
        let result = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 1, timestamp: 1000)
        #expect(result == .error(message: "Acceptance blocked: This request is already concluded or closed."))
    }

    // MARK: - cancel / dropOff / expire

    @Test("Cancel restores quantity and returns request to Posted")
    func cancelRestores() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 5)
        guard case let .success(claimId) = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 5, timestamp: 1000) else {
            Issue.record("claim failed"); return
        }
        // full claim → Claimed; cancel should restore to 5 and Posted
        let ok = try await store.cancelClaimTransaction(claimId: claimId, donorId: "d", timestamp: 2000)
        #expect(ok)
        let req = try await store.request(id: reqId)
        #expect(req?.quantityRemaining == 5)
        #expect(req?.status == RequestStatus.posted.rawValue)
        let claim = try await store.claim(id: claimId)
        #expect(claim?.claimStatus == ClaimStatus.cancelled.rawValue)
    }

    @Test("Cancel is blocked once dropped off")
    func cancelBlockedAfterDropOff() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 3)
        guard case let .success(claimId) = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 3, timestamp: 1000) else {
            Issue.record("claim failed"); return
        }
        _ = try await store.dropOffClaimTransaction(claimId: claimId, timestamp: 1500)
        let ok = try await store.cancelClaimTransaction(claimId: claimId, donorId: "d", timestamp: 2000)
        #expect(ok == false)
    }

    @Test("Drop-off flips fully-claimed request to Dropped Off")
    func dropOff() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 3)
        guard case let .success(claimId) = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 3, timestamp: 1000) else {
            Issue.record("claim failed"); return
        }
        let ok = try await store.dropOffClaimTransaction(claimId: claimId, timestamp: 1500)
        #expect(ok)
        let claim = try await store.claim(id: claimId)
        #expect(claim?.claimStatus == ClaimStatus.droppedOff.rawValue)
        #expect(claim?.dropoffConfirmationTimestamp == 1500)
        let req = try await store.request(id: reqId)
        #expect(req?.status == RequestStatus.droppedOff.rawValue)   // remaining == 0
    }

    @Test("Expire cancels claim, restores quantity, sets expiry reason")
    func expire() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 4)
        guard case let .success(claimId) = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 2, timestamp: 1000) else {
            Issue.record("claim failed"); return
        }
        let ok = try await store.expireClaimTransaction(claimId: claimId, timestamp: 3000)
        #expect(ok)
        let claim = try await store.claim(id: claimId)
        #expect(claim?.claimStatus == ClaimStatus.cancelled.rawValue)
        #expect(claim?.rejectionReason == "Claim expired (time limit elapsed)")
        let req = try await store.request(id: reqId)
        #expect(req?.quantityRemaining == 4)  // 2 restored
    }

    // MARK: - reviewClaim

    @Test("Approve a fully-satisfying claim → Confirmed by Food Bank")
    func approveConfirms() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 3)
        guard case let .success(claimId) = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 3, timestamp: 1000) else {
            Issue.record("claim failed"); return
        }
        _ = try await store.dropOffClaimTransaction(claimId: claimId, timestamp: 1500)
        let ok = try await store.reviewClaimTransaction(
            claimId: claimId, approved: true, rejectionReason: nil, timestamp: 2000)
        #expect(ok)
        let claim = try await store.claim(id: claimId)
        #expect(claim?.claimStatus == ClaimStatus.accepted.rawValue)
        #expect(claim?.foodBankReviewResult == ClaimStatus.accepted.rawValue)
        let req = try await store.request(id: reqId)
        #expect(req?.status == RequestStatus.confirmedByFoodBank.rawValue)
    }

    @Test("Reject restores quantity and records the reason")
    func rejectRestores() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 5)
        guard case let .success(claimId) = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 2, timestamp: 1000) else {
            Issue.record("claim failed"); return
        }
        _ = try await store.dropOffClaimTransaction(claimId: claimId, timestamp: 1500)
        let ok = try await store.reviewClaimTransaction(
            claimId: claimId, approved: false,
            rejectionReason: RejectionReason.damagedItem.rawValue, timestamp: 2000)
        #expect(ok)
        let claim = try await store.claim(id: claimId)
        #expect(claim?.claimStatus == ClaimStatus.rejected.rawValue)
        #expect(claim?.rejectionReason == "damaged item")
        let req = try await store.request(id: reqId)
        #expect(req?.quantityRemaining == 5)                    // 3 + 2 restored
        #expect(req?.status == RequestStatus.posted.rawValue)
    }

    @Test("Review only acts on Dropped Off claims")
    func reviewGuard() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 2)
        guard case let .success(claimId) = try await store.claimRequestTransaction(
            donorId: "d", requestId: reqId, quantityToClaim: 2, timestamp: 1000) else {
            Issue.record("claim failed"); return
        }
        // Not dropped off yet → review must be a no-op returning false
        let ok = try await store.reviewClaimTransaction(
            claimId: claimId, approved: true, rejectionReason: nil, timestamp: 2000)
        #expect(ok == false)
    }

    // MARK: - close + audit trail

    @Test("Close writes a SYSTEM_FOOD_BANK audit entry")
    func closeAudit() async throws {
        let store = makeStore()
        let reqId = try await seedRequest(store, needed: 1)
        _ = try await store.closeRequestTransaction(requestId: reqId, timestamp: 9000)
        let req = try await store.request(id: reqId)
        #expect(req?.status == RequestStatus.closed.rawValue)
        let logs = try await store.allAuditLogs()
        let closeLog = logs.first { $0.actionType == AuditAction.requestClosed.rawValue }
        #expect(closeLog?.donorId == "SYSTEM_FOOD_BANK")
        #expect(closeLog?.claimId == 0)
        #expect(closeLog?.newStatus == RequestStatus.closed.rawValue)
    }

    @Test("Auto-increment ids are sequential")
    func sequentialIds() async throws {
        let store = makeStore()
        let a = try await seedRequest(store, needed: 1)
        let b = try await seedRequest(store, needed: 1)
        #expect(a == 1)
        #expect(b == 2)
    }
}
