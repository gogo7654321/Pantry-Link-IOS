//
//  DemoAccountSetupTests.swift
//  Pantry Link IOSTests
//
//  Ensures a fixed demo donor account exists in the live Firebase project so the UI test can
//  sign in reliably (the sign-in screen is just email + password — no long form to automate).
//  Idempotent: creates the account if missing, otherwise signs in to confirm.
//

import Testing
import Foundation
@testable import Pantry_Link_IOS

@MainActor
@Suite("Demo account setup")
struct DemoAccountSetupTests {

    static let email = "donor-demo@pantrylink.test"
    static let password = "demo123456"

    @Test("Ensure demo donor exists")
    func ensureDemoDonor() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else { Issue.record("no firebase"); return }
        let auth = FirebaseAuthService()
        let profiles = FirebaseProfileService()

        let user: AuthUser
        do {
            user = try await auth.signUp(email: Self.email, password: Self.password)
        } catch {
            // Already exists → sign in to confirm the credentials work.
            user = try await auth.signIn(email: Self.email, password: Self.password)
        }
        #expect(!user.uid.isEmpty)

        var profile = UserProfile(email: Self.email, role: "Donor", name: "Demo Donor", phone: "5550001111")
        profile.donorZip = "30308"
        await profiles.saveUserProfile(uid: user.uid, profile: profile)
        auth.signOut()   // leave signed out so the UI test drives sign-in itself
    }

    static let fbEmail = "foodbank-demo@pantrylink.test"

    @Test("Ensure demo food bank exists")
    func ensureDemoFoodBank() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else { Issue.record("no firebase"); return }
        let auth = FirebaseAuthService()
        let profiles = FirebaseProfileService()

        let user: AuthUser
        do { user = try await auth.signUp(email: Self.fbEmail, password: Self.password) }
        catch { user = try await auth.signIn(email: Self.fbEmail, password: Self.password) }
        #expect(!user.uid.isEmpty)

        var profile = UserProfile(email: Self.fbEmail, role: "Food Bank", name: "Demo Community Pantry", phone: "4702091835")
        profile.fbAddress = "650 Ponce De Leon Ave NE"
        profile.fbCity = "Atlanta"; profile.fbZip = "30308"
        profile.fbSize = "Medium (100-500/wk)"; profile.fbHours = "Mon-Fri 9 AM - 5 PM"; profile.fbColdStorage = true
        await profiles.saveUserProfile(uid: user.uid, profile: profile)
        auth.signOut()
    }

    /// Signs in as the Food Bank demo and persists the session (Firebase + local) WITHOUT
    /// signing out, so a subsequent plain app launch auto-enters the Food Bank workspace.
    @Test("Seed a live Food Bank session for screenshotting")
    func seedFoodBankSession() async throws {
        PantryServiceFactory.configureFirebase()
        guard PantryServiceFactory.isFirebaseAvailable else { Issue.record("no firebase"); return }
        let auth = FirebaseAuthService()
        let profiles = FirebaseProfileService()
        let user = try await auth.signIn(email: Self.fbEmail, password: Self.password)
        let profile = await profiles.fetchUserProfile(uid: user.uid)
            ?? UserProfile(email: Self.fbEmail, role: "Food Bank", name: "Demo Community Pantry", phone: "4702091835")
        PantrySessionStore().save(
            session: PantryUserSession(email: user.email, uid: user.uid, isDemo: false),
            role: "Food Bank", profile: profile)
        // Intentionally NOT signing out.
    }
}
