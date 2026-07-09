//
//  PantrySessionStore.swift
//  Pantry Link IOS
//
//  Port of the SharedPreferences persistence in PantryLinkViewModel.kt
//  (saveSessionToPrefs / clearSessionFromPrefs / loadUserProfileFromPrefs).
//  Backed by UserDefaults. Session, role and profile survive app relaunch, exactly like
//  the Android "pantry_link_prefs" store.
//

import Foundation

struct PantrySessionStore {

    private let defaults: UserDefaults
    private let sessionKey = "pantry_session"
    private let roleKey    = "pantry_selected_role"
    private let profileKey = "pantry_profile"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: - Save

    func save(session: PantryUserSession, role: String, profile: UserProfile?) {
        defaults.set(try? JSONEncoder().encode(session), forKey: sessionKey)
        defaults.set(role, forKey: roleKey)
        if let profile {
            defaults.set(try? JSONEncoder().encode(profile), forKey: profileKey)
        }
    }

    func save(profile: UserProfile) {
        defaults.set(try? JSONEncoder().encode(profile), forKey: profileKey)
    }

    func save(role: String) {
        defaults.set(role, forKey: roleKey)
    }

    // MARK: - Load

    func loadSession() -> PantryUserSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(PantryUserSession.self, from: data)
    }

    func loadRole() -> String {
        defaults.string(forKey: roleKey) ?? PantryRole.donor.rawValue
    }

    func loadProfile() -> UserProfile? {
        guard let data = defaults.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    // MARK: - Clear (Kotlin: clearSessionFromPrefs)

    func clear() {
        defaults.removeObject(forKey: sessionKey)
        defaults.removeObject(forKey: profileKey)
        // role intentionally retained across sign-out, matching the Android default behaviour
        // of remembering the last selected workspace.
    }
}
