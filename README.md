# Pantry Link IOS

A native **iOS 26 / SwiftUI** port of the PantryLink Georgia food-rescue app — connecting
donors with local food banks. Built with Liquid Glass, SwiftData, and Firebase, sharing the
**same Firestore backend** as the Android app (identical collections, document ids, and fields).

## Features

- **Two account types (locked at sign-up):**
  - **Donor** — Dashboard, Browse Needs, Map Finder, My Claims. Claim requests, track drop-offs, earn recognition badges.
  - **Food Bank** — Inventory Needs, Post Requests, Verify Deliveries, Audit Trail, Profile.
- **Live Firebase** — Email/Password Auth + Cloud Firestore, with real-time sync so data created on either app appears on both.
- **Native iOS 26** — bottom `TabView` Liquid Glass bar, large navigation titles, `.searchable`, MapKit with Apple/Google Maps directions, haptics, and a Reduce-Transparency fallback.
- **App Store ready** — privacy manifest (`PrivacyInfo.xcprivacy`), in-app Privacy Policy & Terms, in-app account deletion for all users, and a support contact.

## Architecture

- **Data:** SwiftData `@Model` store behind a `@ModelActor` (`PantryLinkStore`) that mirrors the Android Room transactions 1:1, exposed through `PantryLinkRepository`.
- **Sync:** `FirestorePantrySync` pushes local mutations and listens to the shared collections (`food_banks`, `requests`, `claims`).
- **State:** `@Observable @MainActor PantryLinkViewModel`.
- **Services behind protocols:** `AuthService`, `RemoteProfileService`, `DiagnosticsProbe` — Firebase implementations with local/offline fallbacks.

## Setup

This project uses the Firebase Apple SDK via Swift Package Manager (resolved automatically by Xcode).

1. Open `Pantry Link IOS.xcodeproj` in Xcode 26+.
2. **Add your own `GoogleService-Info.plist`** to `Pantry Link IOS/Pantry Link IOS/` — it is intentionally **git-ignored** and never committed. Download it from your Firebase project (`Project Settings → Your apps → iOS`).
3. In the Firebase console, enable **Authentication → Email/Password** and **Cloud Firestore**.
4. Select an iOS Simulator (e.g. iPhone 17 Pro) and Run.

> Security: no API keys, service-account files, or `.env` secrets are committed. See `.gitignore`.

## Support

Questions or help: **pantrylinkgeorgia@gmail.com**
