//
//  FirebaseServices.swift
//  Pantry Link IOS
//
//  Real Firebase-backed implementations of the service seams (AuthService /
//  RemoteProfileService / DiagnosticsProbe). This is what makes auth + profile sync +
//  food-bank publishing hit the live `pantrylink-ga` project, exactly like the Android app
//  (FirebaseAuth + Firestore "users" / "food_banks" collections).
//
//  If FirebaseApp isn't configured (e.g. plist missing / offline), PantryServiceFactory
//  falls back to the local offline implementations so the app still runs.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firebase Auth

final class FirebaseAuthService: AuthService {
    let isRemote = true

    var currentUser: AuthUser? {
        guard let u = Auth.auth().currentUser else { return nil }
        return AuthUser(email: u.email ?? "", uid: u.uid)
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return AuthUser(email: result.user.email ?? email, uid: result.user.uid)
        } catch {
            throw Self.mapped(error)
        }
    }

    func signUp(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            return AuthUser(email: result.user.email ?? email, uid: result.user.uid)
        } catch {
            throw Self.mapped(error)
        }
    }

    func signOut() { try? Auth.auth().signOut() }

    func deleteCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.noSession }
        do { try await user.delete() } catch { throw Self.mapped(error) }
    }

    func reloadCurrentUser() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        do { try await user.reload(); return Auth.auth().currentUser != nil }
        catch { return false }
    }

    /// Firebase Auth errors carry user-readable localized descriptions; surface them directly.
    private static func mapped(_ error: Error) -> AuthError {
        .message(error.localizedDescription)
    }
}

// MARK: - Firestore profile store

struct FirebaseProfileService: RemoteProfileService {
    nonisolated init() {}

    private var db: Firestore { Firestore.firestore() }

    func saveUserProfile(uid: String, profile: UserProfile) async {
        try? await db.collection("users").document(uid).setData(Self.dict(from: profile))
    }

    func fetchUserProfile(uid: String) async -> UserProfile? {
        guard let snapshot = try? await db.collection("users").document(uid).getDocument(),
              let data = snapshot.data() else { return nil }
        return Self.profile(from: data)
    }

    func deleteUserProfile(uid: String) async {
        try? await db.collection("users").document(uid).delete()
    }

    func saveFoodBankDocument(_ foodBank: FoodBankDTO) async {
        let doc: [String: Any] = [
            "id": foodBank.id, "name": foodBank.name, "address": foodBank.address,
            "zipCode": foodBank.zipCode, "city": foodBank.city, "state": foodBank.state,
            "latitude": foodBank.latitude, "longitude": foodBank.longitude,
            "phone": foodBank.phone, "email": foodBank.email, "verified": foodBank.verified,
            "size": foodBank.size, "operatingHours": foodBank.operatingHours,
            "coldStorage": foodBank.coldStorage
        ]
        try? await db.collection("food_banks").document(String(foodBank.id)).setData(doc)
    }

    func deleteFoodBankDocuments(email: String) async {
        guard let snapshot = try? await db.collection("food_banks")
            .whereField("email", isEqualTo: email).getDocuments() else { return }
        for doc in snapshot.documents { try? await doc.reference.delete() }
    }

    // MARK: Mapping

    static func dict(from p: UserProfile) -> [String: Any] {
        [
            "email": p.email, "role": p.role, "name": p.name, "phone": p.phone,
            "isDemo": p.isDemo, "createdAt": p.createdAt,
            "donorZip": p.donorZip, "donorCity": p.donorCity,
            "donorCanServeType": p.donorCanServeType, "donorCanServeQty": p.donorCanServeQty,
            "donorFrequency": p.donorFrequency,
            "fbAddress": p.fbAddress, "fbCity": p.fbCity, "fbZip": p.fbZip,
            "fbSize": p.fbSize, "fbHours": p.fbHours, "fbColdStorage": p.fbColdStorage
        ]
    }

    static func profile(from d: [String: Any]) -> UserProfile {
        var p = UserProfile()
        p.email = d["email"] as? String ?? ""
        p.role = d["role"] as? String ?? "Donor"
        p.name = d["name"] as? String ?? ""
        p.phone = d["phone"] as? String ?? ""
        p.isDemo = d["isDemo"] as? Bool ?? false
        p.createdAt = (d["createdAt"] as? NSNumber)?.int64Value ?? 0
        p.donorZip = d["donorZip"] as? String ?? ""
        p.donorCity = d["donorCity"] as? String ?? ""
        p.donorCanServeType = d["donorCanServeType"] as? String ?? ""
        p.donorCanServeQty = d["donorCanServeQty"] as? String ?? ""
        p.donorFrequency = d["donorFrequency"] as? String ?? ""
        p.fbAddress = d["fbAddress"] as? String ?? ""
        p.fbCity = d["fbCity"] as? String ?? ""
        p.fbZip = d["fbZip"] as? String ?? ""
        p.fbSize = d["fbSize"] as? String ?? ""
        p.fbHours = d["fbHours"] as? String ?? ""
        p.fbColdStorage = d["fbColdStorage"] as? Bool ?? false
        return p
    }
}

// MARK: - Live diagnostics (Kotlin: runDiagnostics — genuinely probes Firebase)

struct FirebaseDiagnosticsProbe: DiagnosticsProbe {
    nonisolated init() {}

    func run() async -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []

        // 1. Firebase Auth
        if let app = FirebaseApp.app() {
            items.append(DiagnosticItem(name: "Firebase Auth", status: .success,
                message: "Connected (App ID: \(app.options.googleAppID))"))
        } else {
            items.append(DiagnosticItem(name: "Firebase Auth", status: .failure,
                message: "FirebaseApp is not configured."))
        }

        // 2. Firestore read/write round-trip
        let db = Firestore.firestore()
        let ref = db.collection("connection_check").document("test_write")
        do {
            try await ref.setData(["test": true, "timestamp": Int64(Date().timeIntervalSince1970 * 1000)])
            _ = try await ref.getDocument()
            try? await ref.delete()
            items.append(DiagnosticItem(name: "Firestore Database", status: .success,
                message: "Read/Write verification passed successfully."))
        } catch {
            items.append(DiagnosticItem(name: "Firestore Database", status: .failure,
                message: "Connection failed: \(error.localizedDescription)"))
        }

        // 3 & 4. Places / Gemini — keys not bundled in this build (matches Kotlin's key check).
        items.append(DiagnosticItem(name: "Google Places API", status: .failure,
            message: "Places API key is missing or unconfigured."))
        items.append(DiagnosticItem(name: "Gemini API", status: .failure,
            message: "Gemini API key is missing or unconfigured."))
        return items
    }
}

// MARK: - Factory (Firebase when configured, local otherwise)

enum PantryServiceFactory {
    /// Set to `true` ONLY to preview the UI on an iOS 27 *beta* device.
    ///
    /// Firebase's prebuilt Firestore/gRPC binary calls a private libdispatch selector
    /// (`-[OS_dispatch_mach_msg _setContext:]`) that the iOS 27 beta removed, which crashes the
    /// app at launch on iOS 27 betas only. iOS 26 (the shipping OS that App Review and real users
    /// run) is unaffected. When this flag is `true`, Firebase is never configured, so the app runs
    /// fully offline/local and that crash can't happen — handy for demoing the UI on a beta phone.
    ///
    /// MUST be `false` for TestFlight / App Store builds (otherwise auth + cloud sync are disabled).
    static let offlinePreviewMode = false

    static func configureFirebase() {
        if offlinePreviewMode {
            print("[PantryLink] Offline preview mode — Firebase not configured (running local-only).")
            return
        }

        guard FirebaseApp.app() == nil else { return }
        // `FirebaseApp.configure()` raises an (uncatchable) ObjC exception and crashes the app at
        // launch if GoogleService-Info.plist isn't in the bundle. Guard on the plist so a missing
        // config degrades to offline/local mode instead of a launch crash.
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[PantryLink] GoogleService-Info.plist missing — running in offline mode.")
            return
        }
        FirebaseApp.configure()
    }

    static var isFirebaseAvailable: Bool { FirebaseApp.app() != nil }

    static func auth() -> AuthService {
        isFirebaseAvailable ? FirebaseAuthService() : LocalAuthService()
    }
    static func profile() -> RemoteProfileService {
        isFirebaseAvailable ? FirebaseProfileService() : NoOpRemoteProfileService()
    }
    static func diagnostics() -> DiagnosticsProbe {
        isFirebaseAvailable ? FirebaseDiagnosticsProbe() : LocalDiagnosticsProbe()
    }
}
