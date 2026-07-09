//
//  PantrySyncManager.swift
//  Pantry Link IOS
//
//  Port of the Firebase sync surface (com.example.data.FirebaseSyncManager.kt).
//  The Android repository pushes every local mutation up to Firestore. We model that
//  as a protocol so the data layer compiles and runs with zero external dependencies;
//  the concrete Firebase implementation is wired in during the networking slice.
//
//  DTO snapshots (Sendable) cross the actor boundary — never the @Model objects.
//

import Foundation

protocol PantrySyncManager: Sendable {
    func pushRequest(_ request: RequestDTO) async
    func pushClaim(_ claim: ClaimDTO) async
    func pushFoodBank(_ foodBank: FoodBankDTO) async
    func deleteRequestOnRemote(id: Int) async
}

/// Default no-op sync used for offline/demo mode and until Firestore is wired in.
/// Mirrors the Android app's graceful "works fully offline" fallback.
struct NoOpSyncManager: PantrySyncManager {
    // nonisolated so it can be used as a default argument (evaluated in a nonisolated
    // context) despite the module's MainActor-by-default isolation.
    nonisolated init() {}
    func pushRequest(_ request: RequestDTO) async {}
    func pushClaim(_ claim: ClaimDTO) async {}
    func pushFoodBank(_ foodBank: FoodBankDTO) async {}
    func deleteRequestOnRemote(id: Int) async {}
}
