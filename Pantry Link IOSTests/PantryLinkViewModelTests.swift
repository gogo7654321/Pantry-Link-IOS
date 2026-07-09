//
//  PantryLinkViewModelTests.swift
//  Pantry Link IOSTests
//
//  Behavior tests for the ported ViewModel layer: offline auth round-trips, claim
//  orchestration through the repository, distance math, coordinate fallbacks, validation.
//

import Testing
import Foundation
@testable import Pantry_Link_IOS

@MainActor
@Suite("PantryLinkViewModel behavior")
struct PantryLinkViewModelTests {

    private func makeVM() -> (vm: PantryLinkViewModel, repo: PantryLinkRepository) {
        let container = PantryPersistence.makeContainer(inMemory: true)
        let store = PantryLinkStore(modelContainer: container)
        let repo = PantryLinkRepository(store: store)
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm = PantryLinkViewModel(
            repository: repo,
            auth: LocalAuthService(defaults: defaults),
            sessionStore: PantrySessionStore(defaults: defaults)
        )
        return (vm, repo)
    }

    // MARK: - LocationHelper

    @Test("ZIP-only address resolves through the address table, not just the ZIP table")
    func coordsFallback() {
        let roswell = LocationHelper.coords(address: "", zip: "30075")
        #expect(roswell == GeoCoord(latitude: 34.0175, longitude: -84.3612))
        let zipOnly = LocationHelper.coordsForZip("30075")
        #expect(zipOnly == GeoCoord(latitude: 34.0232, longitude: -84.3615))
        #expect(LocationHelper.coordsForZip("99999") == LocationHelper.defaultCenter)
    }

    @Test("Distance from a point to itself is zero")
    func distanceZero() {
        let d = LocationHelper.distanceInMiles(33.7756, -84.3963, 33.7756, -84.3963)
        #expect(abs(d) < 0.0001)
    }

    // MARK: - Validation

    @Test("Email validation")
    func emailValidation() {
        #expect(PantryLinkViewModel.isValidEmail("donor@example.com"))
        #expect(!PantryLinkViewModel.isValidEmail("nope"))
        #expect(!PantryLinkViewModel.isValidEmail("a@b"))
    }

    // MARK: - Auth

    @Test("Donor sign-up creates a session and triggers the rewards dialog")
    func signUpDonor() async {
        let (vm, _) = makeVM()
        let (ok, _) = await vm.signUp(
            email: "donor@x.com", password: "secret1", role: "Donor",
            name: "Dana", phone: "5551234567", donorZip: "30075")
        #expect(ok)
        #expect(vm.userSession?.email == "donor@x.com")
        #expect(vm.currentUserProfile?.role == "Donor")
        #expect(vm.showWelcomeRewardsDialog)
    }

    @Test("Sign-up then sign-out then sign-in restores the session")
    func signInRoundTrip() async {
        let (vm, _) = makeVM()
        _ = await vm.signUp(email: "u@x.com", password: "secret1", role: "Donor", name: "U", phone: "5551112222")
        vm.signOutUser()
        #expect(vm.userSession == nil)
        let (ok, _) = await vm.signIn(email: "u@x.com", password: "secret1")
        #expect(ok)
        #expect(vm.userSession?.email == "u@x.com")
    }

    @Test("Wrong password fails sign-in")
    func wrongPassword() async {
        let (vm, _) = makeVM()
        _ = await vm.signUp(email: "u@x.com", password: "secret1", role: "Donor", name: "U", phone: "5551112222")
        vm.signOutUser()
        let (ok, msg) = await vm.signIn(email: "u@x.com", password: "wrong")
        #expect(!ok)
        #expect(msg == "Incorrect email or password.")
    }

    @Test("Duplicate email is rejected")
    func duplicateEmail() async {
        let (vm, _) = makeVM()
        _ = await vm.signUp(email: "dupe@x.com", password: "secret1", role: "Donor", name: "A", phone: "5550000000")
        let (ok, msg) = await vm.signUp(email: "dupe@x.com", password: "secret2", role: "Donor", name: "B", phone: "5550000001")
        #expect(!ok)
        #expect(msg == "An account with this email already exists.")
    }

    @Test("Weak password and bad email are rejected with exact messages")
    func signUpValidation() async {
        let (vm, _) = makeVM()
        let (ok1, msg1) = await vm.signUp(email: "a@b.com", password: "123", role: "Donor", name: "A", phone: "5550000000")
        #expect(!ok1)
        #expect(msg1 == "Password must be at least 6 characters.")
        let (ok2, msg2) = await vm.signUp(email: "bad", password: "secret1", role: "Donor", name: "A", phone: "5550000000")
        #expect(!ok2)
        #expect(msg2 == "Please enter a valid email address.")
    }

    @Test("Food Bank sign-up persists a food bank into the store")
    func foodBankSignUpPersists() async {
        let (vm, _) = makeVM()
        let (ok, _) = await vm.signUp(
            email: "bank@x.com", password: "secret1", role: "Food Bank",
            name: "Midtown Pantry", phone: "4702091835",
            fbAddress: "650 Ponce De Leon Ave NE", fbCity: "Atlanta", fbZip: "30308")
        #expect(ok)
        #expect(vm.foodBanks.contains { $0.email == "bank@x.com" })
        #expect(!vm.showWelcomeRewardsDialog)   // rewards dialog is donor-only
    }

    // MARK: - Claim orchestration

    @Test("Claiming updates claims, decrements the request, and sets a toast")
    func claimOrchestration() async {
        let (vm, repo) = makeVM()
        _ = await vm.signUp(email: "donor@x.com", password: "secret1", role: "Donor", name: "D", phone: "5551110000")
        let reqId = try! await repo.insertRequest(RequestDTO(
            id: 0, foodBankId: 1, foodBankName: "Bank", title: "Beans", category: "Canned Foods",
            itemDescription: "cans", quantityNeeded: 5, quantityRemaining: 5, deadline: "2026-12-31",
            dropOffLocation: "loc", extraNotes: "", status: RequestStatus.posted.rawValue))
        await vm.refreshAll()

        let (ok, _) = await vm.claimRequest(requestId: reqId, quantity: 2)
        #expect(ok)
        #expect(vm.claims.count == 1)
        #expect(vm.requests.first { $0.id == reqId }?.quantityRemaining == 3)
        #expect(vm.toastMessage == "Claim successfully reserved. Check active dashboard!")
        #expect(vm.activePushAlert != nil)
    }

    // MARK: - Distance & saved locations

    @Test("ZIP-mode distance returns near value for same ZIP")
    func zipDistance() {
        let (vm, _) = makeVM()
        vm.hasLocationPermission = false
        vm.userZipCode = "30308"
        let bank = FoodBankDTO(id: 1, name: "B", address: "", zipCode: "30308", city: "", state: "GA",
                               latitude: 0, longitude: 0, phone: "", email: "", verified: true,
                               size: "", operatingHours: "", coldStorage: false)
        #expect(vm.getDistanceToFoodBank(bank) == 1.2)
    }

    @Test("Saved location validation")
    func savedLocationValidation() {
        let (vm, _) = makeVM()
        vm.addSavedLocation(name: "", address: "", zipCode: "")
        #expect(vm.savedLocations.isEmpty)
        #expect(vm.toastMessage == "Failed: Fields cannot be empty.")
        vm.addSavedLocation(name: "Home", address: "1 St", zipCode: "30308")
        #expect(vm.savedLocations.count == 1)
    }

    @Test("Diagnostics produce four results")
    func diagnostics() async {
        let (vm, _) = makeVM()
        await vm.runDiagnostics()
        #expect(vm.diagnostics?.count == 4)
        #expect(vm.diagnostics?.first?.name == "Firebase Auth")
    }
}
