//
//  PushNotifications.swift
//  Pantry Link IOS
//
//  Remote push via Firebase Cloud Messaging (FCM) + APNs. Every install subscribes to the
//  broadcast topic ("all"), so an admin can send ONE notification to every user from the
//  Firebase console (Engage → Messaging → new campaign → target the "all" topic) WITHOUT
//  shipping any further app update. This is the update-free, user-wide notification channel.
//
//  Why an AppDelegate: `FirebaseAppDelegateProxyEnabled` is false in Info.plist (GUL swizzling
//  off), so we must forward the APNs device token to Messaging ourselves in
//  didRegisterForRemoteNotificationsWithDeviceToken — FCM can't get its token otherwise.
//
//  ── Apple-side setup required before any push actually delivers (done ONCE, outside this repo) ──
//   1. developer.apple.com → Identifiers → org.pantrylink.app → enable the "Push Notifications" capability.
//   2. Create an APNs Auth Key (.p8) and upload it in Firebase console → Project Settings →
//      Cloud Messaging → Apple app configuration.
//   3. In Xcode, add the "Push Notifications" capability to the target (this file already ships the
//      matching aps-environment entitlement; automatic signing regenerates the profile).
//  Until (1)+(2) are done, the app builds and runs fine — it just won't receive remote pushes yet.
//

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// The topic every install subscribes to. Broadcast to this from the Firebase console to reach all users.
let kBroadcastTopic = "all"

/// Minimal UIApplicationDelegate that wires APNs + FCM. Attached to the SwiftUI App via
/// `@UIApplicationDelegateAdaptor`. Does nothing when Firebase isn't configured (offline/preview),
/// so it never crashes a local-only build.
final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // App.init() has already run PantryServiceFactory.configureFirebase() by this point.
        // Only wire push when Firebase actually came up (offlinePreviewMode / missing plist → skip).
        guard FirebaseApp.app() != nil else { return true }
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        // Ask APNs for a device token. Whether banners are shown is governed by the user's
        // notification authorization (already requested in RootView.task); registration is safe regardless.
        application.registerForRemoteNotifications()
        return true
    }

    /// APNs → Firebase. Mandatory because app-delegate swizzling is disabled.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[PantryLink] Remote notification registration failed: \(error.localizedDescription)")
    }

    /// FCM registration token arrived (or refreshed) → (re)subscribe every install to the broadcast topic.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().subscribe(toTopic: kBroadcastTopic) { error in
            if let error {
                print("[PantryLink] Failed to subscribe to '\(kBroadcastTopic)' topic: \(error.localizedDescription)")
            }
        }
    }

    /// Show broadcast notifications while the app is in the FOREGROUND too (not just when backgrounded).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
