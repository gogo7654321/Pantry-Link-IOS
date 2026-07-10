//
//  PantryNotifications.swift
//  Pantry Link IOS
//
//  Real local notifications via UserNotifications. These are genuine system notifications
//  (Notification Center, lock screen, banner when the app is backgrounded) — no server, APNs
//  key, or Push capability required. They fire on real in-app events (claim accepted/rejected,
//  drop-off confirmed, new urgent need, etc.) and respect the user's push toggle + system
//  permission.
//
//  NOTE: delivery while the app is *fully terminated* needs remote push (FCM + an APNs key in
//  the Firebase console + a Cloud Function to send) — that requires account-side setup we can't
//  do from code. Local notifications cover foreground/background, which is what "notifications
//  actually work" means for an event-driven app like this.
//

import Foundation
import UserNotifications

enum PantryNotifications {

    /// Ask the user for permission to show notifications. Safe to call repeatedly — iOS only
    /// prompts once, then no-ops.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Post a real local notification immediately (delivered by the system). Only fires if the
    /// user has granted permission; otherwise it silently does nothing.
    static func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // Immediate delivery (trigger: nil = "as soon as possible").
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
