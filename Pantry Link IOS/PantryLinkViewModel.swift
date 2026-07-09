//
//  PantryLinkViewModel.swift
//  Pantry Link IOS
//
//  Port of com.example.ui.PantryLinkViewModel.kt.
//  Kotlin `StateFlow`s become @Observable stored properties; `viewModelScope.launch { … }`
//  coroutines become `async` methods. Firebase/Firestore/Places/Gemini are reached through
//  the injected services (see PantryServices.swift) so this compiles and runs fully offline.
//  Every validation rule, toast string, push-alert copy and distance calculation matches the
//  Android source.
//
//  Swift 5.9 / iOS 26.4. Uses the real @Observable macro (no @Published, no fabricated APIs).
//

import Foundation
import Observation

@MainActor
@Observable
final class PantryLinkViewModel {

    // MARK: - Dependencies (excluded from observation)

    @ObservationIgnored private let repository: PantryLinkRepository
    @ObservationIgnored private let auth: AuthService
    @ObservationIgnored private let remoteProfile: RemoteProfileService
    @ObservationIgnored private let diagnosticsProbe: DiagnosticsProbe
    @ObservationIgnored private let sessionStore: PantrySessionStore

    // MARK: - Session / profile state

    var diagnostics: [DiagnosticItem]? = nil
    var userSession: PantryUserSession? = nil
    var currentUserProfile: UserProfile? = nil
    var showWelcomeRewardsDialog = false

    /// Roles: "Donor" or "Food Bank"
    var selectedRole: String = PantryRole.donor.rawValue

    // MARK: - Location state

    var hasLocationPermission = true
    var userZipCode = PantryConstants.defaultZip
    var userLatitude = 33.7756       // Midtown Atlanta
    var userLongitude = -84.3963

    // MARK: - Filters & search

    var selectedCategoryFilter = "All"
    var searchQuery = ""
    var maxDistanceFilter = PantryConstants.defaultMaxDistanceMiles

    // MARK: - Database-backed lists (Kotlin: reactive StateFlows via stateIn)

    var foodBanks: [FoodBankDTO] = []
    var partnerFoodBanks: [FoodBankDTO] = []
    var requests: [RequestDTO] = []
    var claims: [ClaimDTO] = []           // current donor's claims
    var allClaims: [ClaimDTO] = []        // every claim (food-bank views)
    var auditLogs: [AuditLogDTO] = []

    // MARK: - Notification & preference state

    var emailNotificationsEnabled = true
    var smsNotificationsEnabled = false
    var pushNotificationsEnabled = true
    var savedLocations: [SavedLocation] = []

    // MARK: - Transient UI signals

    var toastMessage: String? = nil
    var activePushAlert: String? = nil

    // MARK: - Derived

    var currentUserEmail: String { userSession?.email ?? "" }
    func isUserLoggedIn() -> Bool { userSession != nil }

    private var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - Init

    init(
        repository: PantryLinkRepository,
        auth: AuthService = LocalAuthService(),
        remoteProfile: RemoteProfileService = NoOpRemoteProfileService(),
        diagnosticsProbe: DiagnosticsProbe = LocalDiagnosticsProbe(),
        sessionStore: PantrySessionStore = PantrySessionStore()
    ) {
        self.repository = repository
        self.auth = auth
        self.remoteProfile = remoteProfile
        self.diagnosticsProbe = diagnosticsProbe
        self.sessionStore = sessionStore

        // Restore persisted session/role/profile (Kotlin: prefs read in the field initializers).
        self.selectedRole = sessionStore.loadRole()
        self.userSession = sessionStore.loadSession()
            ?? auth.currentUser.map { PantryUserSession(email: $0.email, uid: $0.uid, isDemo: !auth.isRemote) }
        self.currentUserProfile = sessionStore.loadProfile()
        if let profile = currentUserProfile {
            let zip = profile.role == PantryRole.donor.rawValue ? profile.donorZip : profile.fbZip
            if !zip.isEmpty { self.userZipCode = zip }
        }
        updateCoords(forZip: userZipCode)

        Task { [weak self] in
            await self?.refreshSessionAndProfile()
            await self?.refreshAll()
        }
    }

    // MARK: - Toasts & push (Kotlin: _toastMessage / _activePushAlert)

    func showToast(_ message: String) { toastMessage = message }
    func clearToast() { toastMessage = nil }

    func triggerSimulatedPushAlert(title: String, message: String) {
        if pushNotificationsEnabled { activePushAlert = "\(title)\n\(message)" }
    }
    func dismissPushAlert() { activePushAlert = nil }

    // MARK: - Notification toggles

    func toggleEmailNotifications() {
        emailNotificationsEnabled.toggle()
        showToast("Email alerts changed. SMS & Email notification features coming soon!")
    }
    func toggleSMSNotifications() {
        smsNotificationsEnabled.toggle()
        showToast("SMS alerts changed. SMS & Email notification features coming soon!")
    }
    func togglePushNotifications() {
        pushNotificationsEnabled.toggle()
        showToast("Push notifications updated: \(pushNotificationsEnabled)")
    }

    // MARK: - Saved locations

    func addSavedLocation(name: String, address: String, zipCode: String) {
        if name.isBlank || address.isBlank || zipCode.isBlank {
            showToast("Failed: Fields cannot be empty.")
            return
        }
        let newId = (savedLocations.map(\.id).max() ?? 0) + 1
        savedLocations.append(SavedLocation(id: newId, name: name, address: address, zipCode: zipCode))
        showToast("Local saved location '\(name)' added successfully!")
    }

    func removeSavedLocation(id: Int) {
        guard let location = savedLocations.first(where: { $0.id == id }) else { return }
        savedLocations.removeAll { $0.id == id }
        showToast("Removed location '\(location.name)'")
    }

    func dismissWelcomeRewardsDialog() { showWelcomeRewardsDialog = false }

    // MARK: - Filters / role / location setters

    func setRole(_ role: String) {
        selectedRole = role
        sessionStore.save(role: role)
        showToast("Switched to \(role) view")
    }

    func setLocationPermission(_ granted: Bool) {
        hasLocationPermission = granted
        showToast(granted ? "Location access simulated." : "Location denied. Switched to ZIP Code mode.")
    }

    func setZipCode(_ zip: String) {
        userZipCode = zip
        updateCoords(forZip: zip)
    }

    func setCategoryFilter(_ category: String) { selectedCategoryFilter = category }
    func setSearchQuery(_ query: String) { searchQuery = query }
    func setMaxDistanceFilter(_ distance: Double) { maxDistanceFilter = distance }

    /// Kotlin: the _userZipCode collector that snapped coordinates to known metros.
    private func updateCoords(forZip zip: String) {
        switch zip {
        case "30308", "30344": userLatitude = 33.7756; userLongitude = -84.3963   // Atlanta
        case "30075", "30076": userLatitude = 34.0232; userLongitude = -84.3615   // Roswell
        case "30507", "30501": userLatitude = 34.2582; userLongitude = -83.8185   // Gainesville
        case "30909":          userLatitude = 33.4735; userLongitude = -82.0649   // Augusta
        default: break                                                            // keep center
        }
    }

    // MARK: - Coordinate helpers (Kotlin: getCoordsForAddress / getCoordsForZip)

    func getCoordsForAddress(_ address: String, zip: String) -> GeoCoord { LocationHelper.coords(address: address, zip: zip) }
    func getCoordsForZip(_ zip: String) -> GeoCoord { LocationHelper.coordsForZip(zip) }

    // MARK: - Authentication

    func signIn(email: String, password: String) async -> (Bool, String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isBlank || password.isBlank {
            return (false, "Please fill in all fields.")
        }
        do {
            let user = try await auth.signIn(email: trimmedEmail, password: password)
            let session = PantryUserSession(email: user.email, uid: user.uid, isDemo: !auth.isRemote)
            userSession = session
            await syncUserProfile()
            sessionStore.save(session: session, role: selectedRole, profile: currentUserProfile)
            await refreshAll()
            if auth.isRemote {
                showToast("Logged in successfully as \(trimmedEmail)")
                return (true, "Success")
            } else {
                showToast("Logged in as \(trimmedEmail) (Offline Mode)")
                return (true, "DemoSuccess")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func signUp(
        email: String,
        password: String,
        role: String,
        name: String,
        phone: String,
        fbAddress: String = "",
        fbCity: String = "",
        fbZip: String = "",
        fbSize: String = "",
        fbHours: String = "",
        fbColdStorage: Bool = false,
        donorZip: String = "",
        donorCity: String = "",
        donorCanServeType: String = "",
        donorCanServeQty: String = "",
        donorFrequency: String = ""
    ) async -> (Bool, String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isBlank || password.isBlank || trimmedName.isBlank || trimmedPhone.isBlank {
            return (false, "Please fill in all fields.")
        }
        if !Self.isValidEmail(trimmedEmail) {
            return (false, "Please enter a valid email address.")
        }
        if password.count < 6 {
            return (false, "Password must be at least 6 characters.")
        }

        var profile = UserProfile(
            email: trimmedEmail, role: role, name: trimmedName, phone: trimmedPhone,
            isDemo: !auth.isRemote, createdAt: nowMs
        )
        if role == PantryRole.donor.rawValue {
            profile.donorZip = donorZip.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.donorCity = donorCity.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.donorCanServeType = donorCanServeType
            profile.donorCanServeQty = donorCanServeQty
            profile.donorFrequency = donorFrequency
        } else {
            profile.fbAddress = fbAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbCity = fbCity.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbZip = fbZip.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbSize = fbSize
            profile.fbHours = fbHours.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbColdStorage = fbColdStorage
        }

        do {
            let user = try await auth.signUp(email: trimmedEmail, password: password)
            let session = PantryUserSession(email: user.email, uid: user.uid, isDemo: !auth.isRemote)
            userSession = session
            selectedRole = role
            currentUserProfile = profile

            await remoteProfile.saveUserProfile(uid: user.uid, profile: profile)
            sessionStore.save(session: session, role: role, profile: profile)

            // Food Bank: publish to the public map + persist locally (Kotlin food_banks collection).
            if role == PantryRole.foodBank.rawValue {
                let newFbId = Int.random(in: 1000...99999)
                await saveFoodBankLocally(
                    id: newFbId, name: trimmedName, address: profile.fbAddress, zipCode: profile.fbZip,
                    city: profile.fbCity, phone: trimmedPhone, email: trimmedEmail,
                    size: profile.fbSize, hours: profile.fbHours, coldStorage: profile.fbColdStorage
                )
            }

            showToast(auth.isRemote ? "Registered successfully as \(trimmedEmail)"
                                    : "Registered successfully as \(trimmedEmail) (Offline Mode)")
            if role == PantryRole.donor.rawValue { showWelcomeRewardsDialog = true }
            await refreshAll()
            return (true, auth.isRemote ? "Success" : "DemoSuccess")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func updateProfile(
        name: String,
        phone: String,
        donorZip: String = "",
        donorCity: String = "",
        donorCanServeType: String = "",
        donorCanServeQty: String = "",
        donorFrequency: String = "",
        fbAddress: String = "",
        fbCity: String = "",
        fbZip: String = "",
        fbSize: String = "",
        fbHours: String = "",
        fbColdStorage: Bool = false
    ) async -> (Bool, String) {
        guard let session = userSession else { return (false, "Session not found") }
        let email = session.email
        let role = selectedRole

        var profile = currentUserProfile ?? UserProfile()
        profile.email = email
        profile.role = role
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        if role == PantryRole.donor.rawValue {
            profile.donorZip = donorZip.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.donorCity = donorCity.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.donorCanServeType = donorCanServeType
            profile.donorCanServeQty = donorCanServeQty
            profile.donorFrequency = donorFrequency
        } else {
            profile.fbAddress = fbAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbCity = fbCity.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbZip = fbZip.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbSize = fbSize
            profile.fbHours = fbHours.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.fbColdStorage = fbColdStorage

            // Also update the local food bank in the store (Kotlin did the same).
            let existingId = foodBanks.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }?.id
                ?? Int.random(in: 1000...99999)
            await saveFoodBankLocally(
                id: existingId, name: profile.name, address: profile.fbAddress, zipCode: profile.fbZip,
                city: profile.fbCity, phone: profile.phone, email: email,
                size: profile.fbSize, hours: profile.fbHours, coldStorage: profile.fbColdStorage
            )
        }

        currentUserProfile = profile
        sessionStore.save(session: session, role: role, profile: profile)
        await remoteProfile.saveUserProfile(uid: session.uid, profile: profile)
        await refreshAll()
        showToast("Profile updated successfully!")
        return (true, "Success")
    }

    func signOutUser() {
        auth.signOut()
        userSession = nil
        currentUserProfile = nil
        claims = []
        sessionStore.clear()
        showToast("Signed out successfully.")
    }

    func deleteUserAccount() async -> (Bool, String) {
        guard let session = userSession else { return (false, "User session not found.") }
        let email = session.email
        let uid = session.uid
        let role = selectedRole

        await remoteProfile.deleteUserProfile(uid: uid)
        if role == PantryRole.foodBank.rawValue {
            await remoteProfile.deleteFoodBankDocuments(email: email)
            try? await repository.deleteFoodBank(email: email)
        }
        do {
            try await auth.deleteCurrentUser()
            signOutUser()
            await refreshAll()
            return (true, "Success")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func refreshSessionAndProfile() async {
        if auth.currentUser != nil {
            let valid = await auth.reloadCurrentUser()
            if valid {
                await syncUserProfile()
            } else {
                signOutUser()
            }
        } else if let session = userSession, !session.isDemo {
            // A real (non-demo) session with no backing auth user is stale.
            signOutUser()
        }
    }

    private func syncUserProfile() async {
        guard let session = userSession else { return }
        let remote = await remoteProfile.fetchUserProfile(uid: session.uid)
        let profile = remote ?? sessionStore.loadProfile()
        guard let profile else { return }

        selectedRole = profile.role
        currentUserProfile = profile
        let primaryZip = profile.role == PantryRole.donor.rawValue ? profile.donorZip : profile.fbZip
        if !primaryZip.isEmpty { setZipCode(primaryZip) }
        sessionStore.save(session: session, role: profile.role, profile: profile)
    }

    // MARK: - Food bank persistence (Kotlin: saveFoodBankLocally)

    func saveFoodBankLocally(
        id: Int, name: String, address: String, zipCode: String, city: String,
        phone: String, email: String, size: String, hours: String, coldStorage: Bool
    ) async {
        let coord = LocationHelper.coords(address: address, zip: zipCode)
        let dto = FoodBankDTO(
            id: id, name: name, address: address, zipCode: zipCode, city: city, state: "GA",
            latitude: coord.latitude, longitude: coord.longitude, phone: phone, email: email,
            verified: true, size: size, operatingHours: hours, coldStorage: coldStorage
        )
        try? await repository.insertFoodBank(dto)
        await remoteProfile.saveFoodBankDocument(dto)
    }

    // MARK: - Donor operations

    func claimRequest(requestId: Int, quantity: Int) async -> (Bool, String) {
        let result = (try? await repository.tryClaimRequest(
            donorId: currentUserEmail, requestId: requestId, quantityToClaim: quantity, timestamp: nowMs))
            ?? .error(message: "Claim failed.")
        switch result {
        case .success:
            await refreshAll()
            showToast("Claim successfully reserved. Check active dashboard!")
            triggerSimulatedPushAlert(
                title: "Urgent Pantry Claim Reserved",
                message: "Your reservation for \(quantity) items has been logged. Deliver to local food bank to complete!")
            return (true, "Successfully claimed \(quantity) items!")
        case .error(let message):
            showToast("Claim failed: \(message)")
            return (false, message)
        }
    }

    func cancelClaim(claimId: Int) async {
        let success = (try? await repository.tryCancelClaim(
            claimId: claimId, donorId: currentUserEmail, timestamp: nowMs)) ?? false
        if success {
            await refreshAll()
            showToast("Claim cancelled. Quantities restored to the request.")
            triggerSimulatedPushAlert(
                title: "Claim Reservation Cancelled",
                message: "Reservation was cancelled. Help items have been returned to open community needs pool.")
        } else {
            showToast("Cancellation blocked: you have already dropped off this item.")
        }
    }

    func dropOffClaim(claimId: Int) async {
        let success = (try? await repository.markClaimAsDroppedOff(claimId: claimId, timestamp: nowMs)) ?? false
        if success {
            await refreshAll()
            showToast("Item marked as Dropped Off. Awaiting food bank review.")
            triggerSimulatedPushAlert(
                title: "Drop-Off Confirmed",
                message: "A community host has been notified of your drop-off. Awaiting validation review.")
        } else {
            showToast("Failed to update status. Already dropped off or completed.")
        }
    }

    // MARK: - Food Bank operations

    func reviewClaim(claimId: Int, approved: Bool, rejectionReason: String?) async {
        let success = (try? await repository.reviewClaim(
            claimId: claimId, approved: approved, rejectionReason: rejectionReason, timestamp: nowMs)) ?? false
        if success {
            await refreshAll()
            let action = approved ? "Approved" : "Rejected"
            showToast("Claim status set to: \(action).")
            triggerSimulatedPushAlert(
                title: "Drop-off Review Alert",
                message: "Your logged drop-off has been marked as \(action) by the receiving food bank.")
        } else {
            showToast("Failed to issue review decision.")
        }
    }

    func createRequest(
        title: String, category: String, itemDescription: String,
        quantityNeeded: Int, deadline: String, dropOffLocation: String, extraNotes: String
    ) async {
        let foodBank = foodBanks.first { $0.phone == "470-209-1835" } ?? foodBanks.first
        let request = RequestDTO(
            id: 0,
            foodBankId: foodBank?.id ?? 1,
            foodBankName: foodBank?.name ?? "Local Georgia Food Bank",
            title: title, category: category, itemDescription: itemDescription,
            quantityNeeded: quantityNeeded, quantityRemaining: quantityNeeded,
            deadline: deadline, dropOffLocation: dropOffLocation, extraNotes: extraNotes,
            status: RequestStatus.posted.rawValue
        )
        try? await repository.insertRequest(request)
        await refreshAll()
        showToast("New standardized request posted successfully.")
        triggerSimulatedPushAlert(
            title: "New Georgia Pantry Need Indeed",
            message: "New urgent need posted: '\(title)'. Nearby registered donors are being alerted!")
    }

    func closeRequest(requestId: Int) async {
        let success = (try? await repository.closeRequest(requestId: requestId, timestamp: nowMs)) ?? false
        if success {
            await refreshAll()
            showToast("Request successfully closed.")
        }
    }

    func triggerClaimExpiration(claimId: Int) async {
        let success = (try? await repository.expireClaim(claimId: claimId, timestamp: nowMs)) ?? false
        if success {
            await refreshAll()
            showToast("Claim expired. Lock-up released back into available request pool.")
        } else {
            showToast("Blocked: claim cannot expire once dropped off.")
        }
    }

    // MARK: - Distance (Kotlin: getDistanceToFoodBank / calculateDistanceInMiles)

    func getDistanceToFoodBank(_ foodBank: FoodBankDTO) -> Double {
        if !hasLocationPermission {
            // ZIP-based approximation
            if foodBank.zipCode == userZipCode { return 1.2 }
            let bankZip = Int(foodBank.zipCode) ?? 30308
            let userZip = Int(userZipCode) ?? 30308
            let zipDiff = abs(bankZip - userZip)
            if zipDiff == 0 { return 1.5 }
            return min(Double(zipDiff) * 1.8, 45.0)
        }
        return LocationHelper.distanceInMiles(userLatitude, userLongitude, foodBank.latitude, foodBank.longitude)
    }

    // MARK: - Diagnostics

    func clearDiagnostics() { diagnostics = nil }

    func runDiagnostics() async {
        diagnostics = [
            DiagnosticItem(name: "Firebase Auth", status: .pending, message: "Verifying initialization..."),
            DiagnosticItem(name: "Firestore Database", status: .pending, message: "Verifying write & read connectivity..."),
            DiagnosticItem(name: "Google Places API", status: .pending, message: "Verifying API key and query response..."),
            DiagnosticItem(name: "Gemini API", status: .pending, message: "Verifying API key and models endpoint...")
        ]
        diagnostics = await diagnosticsProbe.run()
    }

    // MARK: - Reactive refresh (replaces Kotlin's Flow.stateIn subscriptions)

    func refreshAll() async {
        async let banks = repository.allFoodBanks()
        async let reqs = repository.allRequests()
        async let all = repository.allClaims()
        async let logs = repository.allAuditLogs()

        foodBanks = ((try? await banks) ?? []).map(fixCoords)
        requests = (try? await reqs) ?? []
        allClaims = (try? await all) ?? []
        auditLogs = (try? await logs) ?? []
        claims = currentUserEmail.isBlank ? [] : ((try? await repository.claims(forDonor: currentUserEmail)) ?? [])
    }

    /// Kotlin: foodBanksState mapped banks sitting on the default GA center through the geocoder.
    private func fixCoords(_ bank: FoodBankDTO) -> FoodBankDTO {
        guard bank.latitude == LocationHelper.defaultCenter.latitude,
              bank.longitude == LocationHelper.defaultCenter.longitude else { return bank }
        let coord = LocationHelper.coords(address: bank.address, zip: bank.zipCode)
        return FoodBankDTO(
            id: bank.id, name: bank.name, address: bank.address, zipCode: bank.zipCode, city: bank.city,
            state: bank.state, latitude: coord.latitude, longitude: coord.longitude, phone: bank.phone,
            email: bank.email, verified: bank.verified, size: bank.size,
            operatingHours: bank.operatingHours, coldStorage: bank.coldStorage)
    }

    // MARK: - Validation

    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Small helpers

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
