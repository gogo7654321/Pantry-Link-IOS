//
//  FirestoreSchemaParityTests.swift
//  Pantry Link IOSTests
//
//  Proves cross-app data parity: a request pushed by the iOS sync layer lands in Firestore
//  as the SAME document shape the Android app reads/writes — collection "requests", document
//  id = "\(id)", and every field name/type matching FirebaseSyncManager.kt's toMap(). Uses a
//  high random id (900000+) so it never touches real data, and deletes the doc afterward.
//

import Testing
import Foundation
import FirebaseFirestore
@testable import Pantry_Link_IOS

@MainActor
@Suite("Firestore schema parity")
struct FirestoreSchemaParityTests {

    @Test("iOS-pushed request matches the Android Firestore schema")
    func requestSchema() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else {
            Issue.record("FirebaseApp not configured."); return
        }

        let container = PantryPersistence.makeContainer(inMemory: true)
        let store = PantryLinkStore(modelContainer: container)
        let sync = FirestorePantrySync(store: store)

        let id = Int.random(in: 900000...999999)
        let dto = RequestDTO(
            id: id, foodBankId: 7, foodBankName: "Parity FB", title: "Canned Beans",
            category: "Canned Foods", itemDescription: "Low-sodium cans", quantityNeeded: 10,
            quantityRemaining: 6, deadline: "2026-12-31", dropOffLocation: "123 Peachtree",
            extraNotes: "handle with care", status: "Posted")

        await sync.pushRequest(dto)

        let ref = Firestore.firestore().collection("requests").document(String(id))
        let snap = try await ref.getDocument()
        defer { Task { try? await ref.delete() } }

        #expect(snap.exists)                                   // doc id == "\(id)"
        let d = snap.data() ?? [:]
        #expect((d["id"] as? NSNumber)?.intValue == id)
        #expect(d["foodBankId"] as? NSNumber == 7)
        #expect(d["foodBankName"] as? String == "Parity FB")
        #expect(d["title"] as? String == "Canned Beans")
        #expect(d["category"] as? String == "Canned Foods")
        #expect(d["itemDescription"] as? String == "Low-sodium cans")
        #expect((d["quantityNeeded"] as? NSNumber)?.intValue == 10)
        #expect((d["quantityRemaining"] as? NSNumber)?.intValue == 6)
        #expect(d["deadline"] as? String == "2026-12-31")
        #expect(d["dropOffLocation"] as? String == "123 Peachtree")
        #expect(d["extraNotes"] as? String == "handle with care")
        #expect(d["status"] as? String == "Posted")
        // Exactly the 12 Android fields — no extras that could confuse the Android parser.
        #expect(Set(d.keys) == ["id", "foodBankId", "foodBankName", "title", "category",
                                "itemDescription", "quantityNeeded", "quantityRemaining",
                                "deadline", "dropOffLocation", "extraNotes", "status"])
    }

    @Test("iOS-pushed claim matches the Android Firestore schema (nil→0/empty)")
    func claimSchema() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else { Issue.record("no firebase"); return }

        let container = PantryPersistence.makeContainer(inMemory: true)
        let sync = FirestorePantrySync(store: PantryLinkStore(modelContainer: container))
        let id = Int.random(in: 900000...999999)
        let dto = ClaimDTO(id: id, requestId: 3, requestTitle: "Beans", foodBankName: "FB",
                           donorUserId: "d@x.com", quantityClaimed: 2, claimTimestamp: 1_700_000_000_000,
                           claimStatus: "Claimed", dropoffConfirmationTimestamp: nil,
                           foodBankReviewResult: nil, rejectionReason: nil)
        await sync.pushClaim(dto)

        let ref = Firestore.firestore().collection("claims").document(String(id))
        let snap = try await ref.getDocument()
        defer { Task { try? await ref.delete() } }

        let d = snap.data() ?? [:]
        #expect((d["dropoffConfirmationTimestamp"] as? NSNumber)?.int64Value == 0)  // nil → 0
        #expect(d["foodBankReviewResult"] as? String == "")                          // nil → ""
        #expect(d["rejectionReason"] as? String == "")
        #expect((d["claimTimestamp"] as? NSNumber)?.int64Value == 1_700_000_000_000)
        #expect(d["claimStatus"] as? String == "Claimed")
    }
}
