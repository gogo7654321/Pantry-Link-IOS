//
//  MarketingShotsUITests.swift
//  Pantry Link IOSUITests
//
//  Drives the app through its key screens and captures screenshots for the App Store listing.
//  Run on iPhone 17 Pro Max (6.9") to get the App-Store-required 1320 x 2868 size.
//

import XCTest

final class MarketingShotsUITests: XCTestCase {

    func testSignInShot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestSignedOut"]
        app.launch()
        _ = app.textFields["Email Address"].waitForExistence(timeout: 15)
        sleep(1)
        shot(app, "00_signin")
    }

    func testDonorTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitestDonor"]
        app.launch()

        // Dashboard — welcome + stats + urgent needs
        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 20))
        _ = app.staticTexts["Urgent Needs Near You"].waitForExistence(timeout: 15)
        sleep(3)   // let Firestore mirror sample content into the list
        shot(app, "01_dashboard")

        // Browse needs
        tapTab(app, "Needs"); sleep(3); shot(app, "02_needs")

        // Map finder — try to open a pin callout (Get Directions), else just the map
        tapTab(app, "Map Finder"); sleep(3)
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "pantry")).firstMatch
        if marker.waitForExistence(timeout: 4) { marker.tap(); sleep(2) }
        shot(app, "03_map")

        // My claims
        tapTab(app, "My Claims"); sleep(2); shot(app, "04_claims")

        // Account
        tapTab(app, "Account"); sleep(2); shot(app, "05_account")
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        if b.waitForExistence(timeout: 8) { b.tap() }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
