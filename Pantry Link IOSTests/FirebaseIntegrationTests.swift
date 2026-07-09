//
//  FirebaseIntegrationTests.swift
//  Pantry Link IOSTests
//
//  Live end-to-end proof that Firebase is wired and reachable: configures Firebase from the
//  bundled GoogleService-Info.plist, then exercises the real FirebaseAuthService and
//  FirebaseProfileService against the pantrylink-ga project — create user → write profile to
//  Firestore → read it back → delete profile → delete user (self-cleaning). Runs in the app
//  host process so the Firebase frameworks are loaded and configured.
//

import Testing
import Foundation
@testable import Pantry_Link_IOS

@MainActor
@Suite("Firebase live integration")
struct FirebaseIntegrationTests {

    @Test("Configure → sign up → Firestore round-trip → delete (live)")
    func liveRoundTrip() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else {
            Issue.record("FirebaseApp not configured — GoogleService-Info.plist missing from bundle.")
            return
        }

        let auth = FirebaseAuthService()
        let profiles = FirebaseProfileService()

        let email = "pantry-it-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        let password = "secret123"

        // 1. Create the account against live Firebase Auth.
        let user = try await auth.signUp(email: email, password: password)
        #expect(!user.uid.isEmpty)
        #expect(user.email.lowercased() == email)   // Firebase normalizes email casing

        // 2. Write a profile to Firestore and read it back.
        var profile = UserProfile(email: email, role: "Donor", name: "Integration Test", phone: "5550000000")
        profile.donorZip = "30308"
        await profiles.saveUserProfile(uid: user.uid, profile: profile)

        let fetched = await profiles.fetchUserProfile(uid: user.uid)
        #expect(fetched?.email == email)
        #expect(fetched?.name == "Integration Test")
        #expect(fetched?.donorZip == "30308")

        // 3. Clean up: delete the profile doc and the auth user.
        await profiles.deleteUserProfile(uid: user.uid)
        try await auth.deleteCurrentUser()
        #expect(auth.currentUser == nil)
    }
}
