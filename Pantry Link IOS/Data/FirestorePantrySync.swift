//
//  FirestorePantrySync.swift
//  Pantry Link IOS
//
//  Bidirectional Firestore sync — the iOS counterpart of the Android FirebaseSyncManager.kt.
//  CRITICAL: this reads and writes the SAME Firestore data as the Android app, byte-for-byte:
//    • collections: "food_banks", "requests", "claims"  (audit_logs stays local — the
//      Android repository never pushes it either)
//    • document id = the integer entity id, as a string (e.g. requests/42)
//    • field names/types exactly match Android's toMap() encoders
//  Push happens on local mutation (via PantryLinkRepository); snapshot listeners mirror remote
//  changes back into the local SwiftData store (REPLACE upsert), so a request created in the
//  Android app appears here and vice-versa, with no schema conflicts.
//

import Foundation
import FirebaseFirestore

final class FirestorePantrySync: PantrySyncManager, @unchecked Sendable {
    private let store: PantryLinkStore
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    init(store: PantryLinkStore) { self.store = store }

    // MARK: - Push (local → Firestore). Doc id = "\(id)", fields identical to Android toMap().

    func pushRequest(_ r: RequestDTO) async {
        guard r.id > 0 else { return }
        try? await db.collection("requests").document(String(r.id)).setData([
            "id": r.id, "foodBankId": r.foodBankId, "foodBankName": r.foodBankName,
            "title": r.title, "category": r.category, "itemDescription": r.itemDescription,
            "quantityNeeded": r.quantityNeeded, "quantityRemaining": r.quantityRemaining,
            "deadline": r.deadline, "dropOffLocation": r.dropOffLocation,
            "extraNotes": r.extraNotes, "status": r.status
        ])
    }

    func pushClaim(_ c: ClaimDTO) async {
        guard c.id > 0 else { return }
        try? await db.collection("claims").document(String(c.id)).setData([
            "id": c.id, "requestId": c.requestId, "requestTitle": c.requestTitle,
            "foodBankName": c.foodBankName, "donorUserId": c.donorUserId,
            "quantityClaimed": c.quantityClaimed, "claimTimestamp": c.claimTimestamp,
            "claimStatus": c.claimStatus,
            "dropoffConfirmationTimestamp": c.dropoffConfirmationTimestamp ?? 0,
            "foodBankReviewResult": c.foodBankReviewResult ?? "",
            "rejectionReason": c.rejectionReason ?? ""
        ])
    }

    func pushFoodBank(_ f: FoodBankDTO) async {
        guard f.id > 0 else { return }
        try? await db.collection("food_banks").document(String(f.id)).setData([
            "id": f.id, "name": f.name, "address": f.address, "zipCode": f.zipCode,
            "city": f.city, "state": f.state, "latitude": f.latitude, "longitude": f.longitude,
            "phone": f.phone, "email": f.email, "verified": f.verified, "size": f.size,
            "operatingHours": f.operatingHours, "coldStorage": f.coldStorage
        ])
    }

    func pushAuditLog(_ a: AuditLogDTO) async {
        guard a.id > 0 else { return }
        try? await db.collection("audit_logs").document(String(a.id)).setData([
            "id": a.id, "donorId": a.donorId, "requestId": a.requestId, "claimId": a.claimId,
            "actionType": a.actionType, "timestamp": a.timestamp,
            "oldStatus": a.oldStatus, "newStatus": a.newStatus
        ])
    }

    func deleteRequestOnRemote(id: Int) async {
        guard id > 0 else { return }
        try? await db.collection("requests").document(String(id)).delete()
    }

    // MARK: - Listen (Firestore → local store). Mirrors Android startSync().

    /// Attaches snapshot listeners. `onChange` fires (on the main actor) after each batch of
    /// upserts so the ViewModel can refresh. Safe to call once at startup.
    func startListening(onChange: @escaping @Sendable () -> Void) {
        stopListening()

        // Each listener upserts the current documents, then — only on an authoritative SERVER
        // snapshot (never a possibly-stale/empty cache snapshot, which would wrongly wipe local
        // data while offline) — prunes any local row the server no longer has. `documents` already
        // includes our own pending local writes (Firestore latency compensation), so pruning never
        // removes a doc this device just created but hasn't finished pushing.
        listeners.append(db.collection("food_banks").addSnapshotListener { [store] snap, _ in
            guard let snap else { return }
            let banks = snap.documents.compactMap { Self.parseFoodBank($0) }
            let liveIds = Set(snap.documents.compactMap { Int($0.documentID) })
            let canPrune = !snap.metadata.isFromCache
            Task {
                for b in banks { try? await store.insertFoodBank(b) }
                if canPrune { try? await store.pruneFoodBanks(keeping: liveIds) }
                await MainActor.run(body: onChange)
            }
        })

        listeners.append(db.collection("requests").addSnapshotListener { [store] snap, _ in
            guard let snap else { return }
            let reqs = snap.documents.compactMap { Self.parseRequest($0) }
            let liveIds = Set(snap.documents.compactMap { Int($0.documentID) })
            let canPrune = !snap.metadata.isFromCache
            Task {
                for r in reqs { try? await store.insertRequest(r) }
                if canPrune { try? await store.pruneRequests(keeping: liveIds) }
                await MainActor.run(body: onChange)
            }
        })

        listeners.append(db.collection("claims").addSnapshotListener { [store] snap, _ in
            guard let snap else { return }
            let claims = snap.documents.compactMap { Self.parseClaim($0) }
            let liveIds = Set(snap.documents.compactMap { Int($0.documentID) })
            let canPrune = !snap.metadata.isFromCache
            Task {
                for c in claims { try? await store.upsertClaim(c) }
                if canPrune { try? await store.pruneClaims(keeping: liveIds) }
                await MainActor.run(body: onChange)
            }
        })

        listeners.append(db.collection("audit_logs").addSnapshotListener { [store] snap, _ in
            guard let snap else { return }
            let logs = snap.documents.compactMap { Self.parseAuditLog($0) }
            let liveIds = Set(snap.documents.compactMap { Int($0.documentID) })
            let canPrune = !snap.metadata.isFromCache
            Task {
                for l in logs { try? await store.upsertAuditLog(l) }
                if canPrune { try? await store.pruneAuditLogs(keeping: liveIds) }
                await MainActor.run(body: onChange)
            }
        })
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Parsers (mirror Android parseFoodBank/parseRequest/parseClaim exactly)

    private static func parseFoodBank(_ doc: QueryDocumentSnapshot) -> FoodBankDTO? {
        guard let id = Int(doc.documentID) else { return nil }
        let d = doc.data()
        let address = d["address"] as? String ?? ""
        let zip = d["zipCode"] as? String ?? ""
        let rawLat = (d["latitude"] as? NSNumber)?.doubleValue ?? 33.7490
        let rawLng = (d["longitude"] as? NSNumber)?.doubleValue ?? -84.3880
        // Default GA-center sentinel → resolve via the coordinate table (same as Android).
        let coord: GeoCoord = (rawLat == 33.7490 && rawLng == -84.3880)
            ? LocationHelper.coords(address: address, zip: zip)
            : GeoCoord(latitude: rawLat, longitude: rawLng)
        return FoodBankDTO(
            id: id, name: d["name"] as? String ?? "", address: address, zipCode: zip,
            city: d["city"] as? String ?? "", state: d["state"] as? String ?? "GA",
            latitude: coord.latitude, longitude: coord.longitude,
            phone: d["phone"] as? String ?? "", email: d["email"] as? String ?? "",
            verified: d["verified"] as? Bool ?? true, size: d["size"] as? String ?? "",
            operatingHours: d["operatingHours"] as? String ?? "",
            coldStorage: d["coldStorage"] as? Bool ?? false
        )
    }

    private static func parseRequest(_ doc: QueryDocumentSnapshot) -> RequestDTO? {
        guard let id = Int(doc.documentID) else { return nil }
        let d = doc.data()
        return RequestDTO(
            id: id,
            foodBankId: (d["foodBankId"] as? NSNumber)?.intValue ?? 1,
            foodBankName: d["foodBankName"] as? String ?? "",
            title: d["title"] as? String ?? "",
            category: d["category"] as? String ?? "",
            itemDescription: d["itemDescription"] as? String ?? "",
            quantityNeeded: (d["quantityNeeded"] as? NSNumber)?.intValue ?? 0,
            quantityRemaining: (d["quantityRemaining"] as? NSNumber)?.intValue ?? 0,
            deadline: d["deadline"] as? String ?? "",
            dropOffLocation: d["dropOffLocation"] as? String ?? "",
            extraNotes: d["extraNotes"] as? String ?? "",
            status: d["status"] as? String ?? "Posted"
        )
    }

    private static func parseClaim(_ doc: QueryDocumentSnapshot) -> ClaimDTO? {
        guard let id = Int(doc.documentID) else { return nil }
        let d = doc.data()
        let dropoffRaw = (d["dropoffConfirmationTimestamp"] as? NSNumber)?.int64Value
        let dropoff = (dropoffRaw == 0) ? nil : dropoffRaw
        let reviewRaw = d["foodBankReviewResult"] as? String
        let review = (reviewRaw?.isEmpty ?? true) ? nil : reviewRaw
        let rejRaw = d["rejectionReason"] as? String
        let rejection = (rejRaw?.isEmpty ?? true) ? nil : rejRaw
        return ClaimDTO(
            id: id,
            requestId: (d["requestId"] as? NSNumber)?.intValue ?? 0,
            requestTitle: d["requestTitle"] as? String ?? "",
            foodBankName: d["foodBankName"] as? String ?? "",
            donorUserId: d["donorUserId"] as? String ?? "",
            quantityClaimed: (d["quantityClaimed"] as? NSNumber)?.intValue ?? 0,
            claimTimestamp: (d["claimTimestamp"] as? NSNumber)?.int64Value ?? 0,
            claimStatus: d["claimStatus"] as? String ?? "Claimed",
            dropoffConfirmationTimestamp: dropoff,
            foodBankReviewResult: review,
            rejectionReason: rejection
        )
    }

    private static func parseAuditLog(_ doc: QueryDocumentSnapshot) -> AuditLogDTO? {
        guard let id = Int(doc.documentID) else { return nil }
        let d = doc.data()
        return AuditLogDTO(
            id: id,
            donorId: d["donorId"] as? String ?? "",
            requestId: (d["requestId"] as? NSNumber)?.intValue ?? 0,
            claimId: (d["claimId"] as? NSNumber)?.intValue ?? 0,
            actionType: d["actionType"] as? String ?? "",
            timestamp: (d["timestamp"] as? NSNumber)?.int64Value ?? 0,
            oldStatus: d["oldStatus"] as? String ?? "",
            newStatus: d["newStatus"] as? String ?? ""
        )
    }
}
