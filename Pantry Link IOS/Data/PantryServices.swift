//
//  PantryServices.swift
//  Pantry Link IOS
//
//  Abstractions for the external systems the Android ViewModel talked to directly —
//  Firebase Auth, Firestore, the diagnostics probes (Places/Gemini). Same approach as
//  PantrySyncManager: protocols + working *local* implementations so the app compiles and
//  runs fully offline now; Firebase-backed implementations drop in during a later slice.
//

import Foundation
import CryptoKit

// MARK: - Auth (Kotlin: FirebaseAuth + the offline/demo fallback path)

struct AuthUser: Sendable, Equatable {
    let email: String
    let uid: String
}

enum AuthError: LocalizedError, Equatable {
    case emptyFields
    case invalidEmail
    case weakPassword
    case invalidCredentials
    case emailInUse
    case noSession
    case message(String)

    var errorDescription: String? {
        switch self {
        case .emptyFields:        return "Please fill in all fields."
        case .invalidEmail:       return "Please enter a valid email address."
        case .weakPassword:       return "Password must be at least 6 characters."
        case .invalidCredentials: return "Incorrect email or password."
        case .emailInUse:         return "An account with this email already exists."
        case .noSession:          return "User session not found."
        case .message(let m):     return m
        }
    }
}

protocol AuthService: AnyObject {
    /// True for a real remote backend (Firebase); false for the local/offline store.
    var isRemote: Bool { get }
    var currentUser: AuthUser? { get }
    func signIn(email: String, password: String) async throws -> AuthUser
    func signUp(email: String, password: String) async throws -> AuthUser
    func signOut()
    func deleteCurrentUser() async throws
    /// Returns whether the persisted session is still valid (Kotlin: currentUser.reload()).
    func reloadCurrentUser() async -> Bool
}

/// Offline auth: accounts persisted in UserDefaults, passwords stored as SHA-256 hashes.
/// Mirrors the Android app's graceful offline/demo behaviour so the simulator is fully usable.
final class LocalAuthService: AuthService {

    let isRemote = false
    private let defaults: UserDefaults
    private let accountsKey = "pantry_local_accounts"
    private let currentKey  = "pantry_local_current_uid"

    private struct Account: Codable { let email: String; let uid: String; let passwordHash: String }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func loadAccounts() -> [String: Account] {
        guard let data = defaults.data(forKey: accountsKey),
              let map = try? JSONDecoder().decode([String: Account].self, from: data) else { return [:] }
        return map
    }

    private func saveAccounts(_ map: [String: Account]) {
        defaults.set(try? JSONEncoder().encode(map), forKey: accountsKey)
    }

    private func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var currentUser: AuthUser? {
        guard let uid = defaults.string(forKey: currentKey),
              let account = loadAccounts().values.first(where: { $0.uid == uid }) else { return nil }
        return AuthUser(email: account.email, uid: account.uid)
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        let key = email.lowercased()
        guard let account = loadAccounts()[key], account.passwordHash == hash(password) else {
            throw AuthError.invalidCredentials
        }
        defaults.set(account.uid, forKey: currentKey)
        return AuthUser(email: account.email, uid: account.uid)
    }

    func signUp(email: String, password: String) async throws -> AuthUser {
        let key = email.lowercased()
        var accounts = loadAccounts()
        if accounts[key] != nil { throw AuthError.emailInUse }
        let uid = "local_\(abs(key.hashValue))_\(accounts.count + 1)"
        let account = Account(email: email, uid: uid, passwordHash: hash(password))
        accounts[key] = account
        saveAccounts(accounts)
        defaults.set(uid, forKey: currentKey)
        return AuthUser(email: email, uid: uid)
    }

    func signOut() {
        defaults.removeObject(forKey: currentKey)
    }

    func deleteCurrentUser() async throws {
        guard let uid = defaults.string(forKey: currentKey) else { throw AuthError.noSession }
        var accounts = loadAccounts()
        if let key = accounts.first(where: { $0.value.uid == uid })?.key {
            accounts.removeValue(forKey: key)
            saveAccounts(accounts)
        }
        defaults.removeObject(forKey: currentKey)
    }

    func reloadCurrentUser() async -> Bool { currentUser != nil }
}

// MARK: - Remote profile store (Kotlin: Firestore "users" / "food_banks" collections)

protocol RemoteProfileService: Sendable {
    func saveUserProfile(uid: String, profile: UserProfile) async
    func fetchUserProfile(uid: String) async -> UserProfile?
    func deleteUserProfile(uid: String) async
    func saveFoodBankDocument(_ foodBank: FoodBankDTO) async
    func deleteFoodBankDocuments(email: String) async
}

/// Offline no-op: profiles live in local storage (PantrySessionStore) and the SwiftData store.
struct NoOpRemoteProfileService: RemoteProfileService {
    nonisolated init() {}
    func saveUserProfile(uid: String, profile: UserProfile) async {}
    func fetchUserProfile(uid: String) async -> UserProfile? { nil }
    func deleteUserProfile(uid: String) async {}
    func saveFoodBankDocument(_ foodBank: FoodBankDTO) async {}
    func deleteFoodBankDocuments(email: String) async {}
}

// MARK: - Diagnostics (Kotlin: runDiagnostics — Firebase/Firestore/Places/Gemini checks)

protocol DiagnosticsProbe: Sendable {
    func run() async -> [DiagnosticItem]
}

/// Reports the honest local/offline state, matching the Kotlin behaviour when API keys are
/// unconfigured placeholders (Auth OK in local mode; remote services not configured).
struct LocalDiagnosticsProbe: DiagnosticsProbe {
    nonisolated init() {}
    func run() async -> [DiagnosticItem] {
        [
            DiagnosticItem(name: "Firebase Auth", status: .success,
                           message: "Local offline auth active (Firebase not linked in this build)."),
            DiagnosticItem(name: "Firestore Database", status: .failure,
                           message: "Not configured: running against local SwiftData store."),
            DiagnosticItem(name: "Google Places API", status: .failure,
                           message: "Places API key is missing or unconfigured."),
            DiagnosticItem(name: "Gemini API", status: .failure,
                           message: "Gemini API key is missing or unconfigured.")
        ]
    }
}
