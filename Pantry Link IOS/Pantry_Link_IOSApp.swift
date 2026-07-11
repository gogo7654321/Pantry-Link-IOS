//
//  Pantry_Link_IOSApp.swift
//  Pantry Link IOS
//
//  Created by SUNNY MENDPARA on 7/7/26.
//

import SwiftUI

@main
struct Pantry_Link_IOSApp: App {
    init() {
        // Configure Firebase from GoogleService-Info.plist before any service is built.
        PantryServiceFactory.configureFirebase()

        // UI-test seam — DEBUG builds only, so it is entirely compiled out of App Store (Release)
        // binaries. Seeds an offline demo session so a workspace can be rendered without auth.
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitestFoodBank") {
            var p = UserProfile(email: "demo-fb@local", role: "Food Bank", name: "Demo Community Pantry", phone: "4702091835")
            p.isDemo = true; p.fbAddress = "650 Ponce De Leon Ave NE"; p.fbCity = "Atlanta"; p.fbZip = "30308"
            p.fbSize = "Medium (100-500/wk)"; p.fbHours = "Mon-Fri 9 AM - 5 PM"; p.fbColdStorage = true
            PantrySessionStore().save(
                session: PantryUserSession(email: "demo-fb@local", uid: "uitest-fb", isDemo: true),
                role: "Food Bank", profile: p)
        } else if args.contains("-uitestDonor") {
            var p = UserProfile(email: "pantrylinkgeorgia@gmail.com", role: "Donor", name: "Neil Mendpara", phone: "(770) 555-0142")
            p.isDemo = true; p.donorZip = "30308"
            PantrySessionStore().save(
                session: PantryUserSession(email: "pantrylinkgeorgia@gmail.com", uid: "uitest-donor", isDemo: true),
                role: "Donor", profile: p)
        } else if args.contains("-uitestSignedOut") {
            PantrySessionStore().clear()
            PantryServiceFactory.auth().signOut()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
