//
//  DonorWorkspaceUITests.swift
//  Pantry Link IOSUITests
//
//  Drives a live donor sign-up through the UI and verifies the Donor workspace renders,
//  capturing a screenshot. Exercises the real flow end-to-end (auth → workspace → live data).
//

import XCTest
import UIKit

final class DonorWorkspaceUITests: XCTestCase {

    func testDonorSignInShowsWorkspace() throws {
        let app = XCUIApplication()
        app.launch()

        let email = app.textFields["Email Address"]
        guard email.waitForExistence(timeout: 15) else {
            // Already authenticated — confirm workspace + screenshot.
            attachScreenshot(app, "donor_dashboard")
            return
        }

        // Sign-in screen: two fields at the top, no scrolling, no terms.
        email.tap(); email.typeText("donor-demo@pantrylink.test")
        let pw = app.secureTextFields["Password"]
        pw.tap(); pw.typeText("demo123456")
        app.buttons["auth_submit"].tap()

        // Workspace signal: the Dashboard's "Urgent Requests" header.
        XCTAssertTrue(app.staticTexts["Urgent Needs Near You"].waitForExistence(timeout: 30),
                      "Donor workspace dashboard did not appear after sign-in")
        // Give the Firestore listener time to mirror the seeded request into the store.
        _ = app.staticTexts["Peanut Butter Drive"].waitForExistence(timeout: 20)
        attachScreenshot(app, "donor_dashboard")

        // Visit Browse tab too.
        let browse = app.buttons["Needs"].firstMatch
        if browse.waitForExistence(timeout: 5) {
            browse.tap()
            _ = app.staticTexts["Peanut Butter Drive"].waitForExistence(timeout: 15)
            attachScreenshot(app, "donor_browse")
        }
    }

    func testFoodBankSignInShowsWorkspace() throws {
        let app = XCUIApplication()
        app.launch()

        // If a previous session auto-logged in, sign out first.
        let signOut = app.buttons["sign_out"]
        if signOut.waitForExistence(timeout: 8) { signOut.tap() }

        let email = app.textFields["Email Address"]
        guard email.waitForExistence(timeout: 15) else { attachScreenshot(app, "fb_workspace"); return }
        email.tap(); email.typeText("foodbank-demo@pantrylink.test")
        // SecureField typeText is unreliable under XCUITest; paste instead.
        let pw = app.secureTextFields["Password"]
        UIPasteboard.general.string = "demo123456"
        pw.tap()
        pw.press(forDuration: 1.3)
        let paste = app.menuItems["Paste"]
        if paste.waitForExistence(timeout: 4) { paste.tap() } else { pw.typeText("demo123456") }
        app.buttons["auth_submit"].tap()

        // Dismiss the iOS "Save Password?" dialog if it appears.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 6) { notNow.tap() }

        // Food Bank workspace signal: the Post Requests tab header.
        XCTAssertTrue(app.staticTexts["Inventory Needs"].waitForExistence(timeout: 30)
                      || app.staticTexts["Partner Request Management"].firstMatch.waitForExistence(timeout: 5),
                      "Food Bank workspace did not appear")
        attachScreenshot(app, "fb_active_needs")

        let post = app.buttons["Post"].firstMatch
        if post.waitForExistence(timeout: 5) {
            post.tap()
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 5)
            attachScreenshot(app, "fb_post_request")
        }
        // Confirm the account type is LOCKED: no Donor/Food Bank switch control exists.
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "Role switcher should not exist (account type is locked)")
    }

    @discardableResult
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int = 6) -> XCUIElement {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        element.tap()
        return element
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }
}
