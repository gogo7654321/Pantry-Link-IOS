//
//  DemoSeedTests.swift
//  Pantry Link IOSTests
//
//  Seeds (and later removes) one demo request + its food bank in the live Firestore, in the
//  exact Android schema, so the Donor workspace can be screenshotted with real card content.
//  This also demonstrates the cross-app write path (iOS-written docs are Android-readable).
//

import Testing
import Foundation
import FirebaseFirestore
@testable import Pantry_Link_IOS

@MainActor
@Suite("Demo seed", .serialized)
struct DemoSeedTests {

    private func sync() -> FirestorePantrySync {
        PantryServiceFactory.configureFirebase()
        let container = PantryPersistence.makeContainer(inMemory: true)
        return FirestorePantrySync(store: PantryLinkStore(modelContainer: container))
    }

    @Test("seed demo request + food bank")
    func seed() async throws {
        guard PantryServiceFactory.isFirebaseAvailable else { Issue.record("no firebase"); return }
        let s = sync()
        await s.pushFoodBank(FoodBankDTO(
            id: 990001, name: "Midtown Community Pantry", address: "650 Ponce De Leon Ave NE",
            zipCode: "30308", city: "Atlanta", state: "GA", latitude: 33.7725, longitude: -84.3663,
            phone: "470-209-1835", email: "midtown@pantrylink.test", verified: true,
            size: "Medium (100-500/wk)", operatingHours: "Mon-Fri 9 AM - 5 PM", coldStorage: true))
        await s.pushRequest(RequestDTO(
            id: 990001, foodBankId: 990001, foodBankName: "Midtown Community Pantry",
            title: "Peanut Butter Drive", category: "Canned Foods",
            itemDescription: "16oz jars, unopened, within date", quantityNeeded: 40,
            quantityRemaining: 28, deadline: "Aug 15, 2026",
            dropOffLocation: "650 Ponce De Leon Ave NE, Atlanta", extraNotes: "Label clearly",
            status: "Posted"))
    }

    @Test("saved locations round-trip to Firestore")
    func savedLocationsRoundTrip() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else { Issue.record("no firebase"); return }
        let svc = FirebaseProfileService()
        let uid = "roundtrip_test_uid"
        let sample = [
            SavedLocation(id: 1, name: "Home", address: "233 Peachtree St NE", zipCode: "30303",
                          notes: "Ring the bell", latitude: 33.7592, longitude: -84.3874),
            SavedLocation(id: 2, name: "Office", address: "1280 W Peachtree St NW", zipCode: "30309")
        ]
        await svc.saveSavedLocations(uid: uid, sample)
        let fetched = await svc.fetchSavedLocations(uid: uid)
        print("[roundtrip] saved \(sample.count), fetched \(fetched.count)")
        #expect(fetched.count == 2)
        #expect(fetched.first(where: { $0.id == 1 })?.notes == "Ring the bell")
        #expect(fetched.first(where: { $0.id == 1 })?.latitude == 33.7592)
        // cleanup
        try? await Firestore.firestore().collection("users").document(uid).delete()
    }

    @Test("AUDIT: list all requests from server")
    func auditRequests() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else { Issue.record("no firebase"); return }
        let db = Firestore.firestore()
        let snap = try await db.collection("requests").getDocuments(source: .server)
        print("[audit] requests collection has \(snap.documents.count) docs (from SERVER):")
        for d in snap.documents {
            print("[audit]   id=\(d.documentID) title=\(d.data()["title"] ?? "?") status=\(d.data()["status"] ?? "?")")
        }
        let fb = try await db.collection("food_banks").getDocuments(source: .server)
        print("[audit] food_banks collection has \(fb.documents.count) docs (from SERVER):")
        for d in fb.documents {
            print("[audit]   id=\(d.documentID) name=\(d.data()["name"] ?? "?")")
        }
    }

    @Test("delete demo request + food bank")
    func cleanup() async throws {
        guard PantryServiceFactory.isFirebaseAvailable else { return }
        let db = Firestore.firestore()
        try? await db.collection("requests").document("990001").delete()
        try? await db.collection("food_banks").document("990001").delete()
    }
}
