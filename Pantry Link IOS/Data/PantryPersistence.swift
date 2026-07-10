//
//  PantryPersistence.swift
//  Pantry Link IOS
//
//  Port of com.example.data.AppDatabase.kt (the Room database + builder).
//  Builds the SwiftData ModelContainer, mirroring Room's config:
//    - database name       → "pantry_link_georgia_db"
//    - fallbackToDestructiveMigration → we rebuild the store from scratch if the
//      on-disk schema can't be opened (SwiftData has no lightweight-migration story
//      for arbitrary changes yet, so this matches Room's behaviour of wiping on mismatch)
//    - onCreate populateDatabase → intentionally empty: no seed/fake food banks,
//      matching the Android note "populate reactively as they sign up via the portal".
//
//  Swift 5.9 / iOS 26.4.
//

import Foundation
import SwiftData

enum PantryPersistence {

    static let databaseName = "pantry_link_georgia_db"

    static let schema = Schema([
        FoodBank.self,
        PantryRequest.self,
        Claim.self,
        AuditLog.self
    ])

    /// Builds the on-disk container. Falls back to a fresh store if the existing file
    /// can't be opened under the current schema (Room: fallbackToDestructiveMigration).
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(
            databaseName,
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Destructive fallback: delete the store file and rebuild empty.
            if !inMemory, let url = config.url as URL? {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // Last resort: an in-memory store so the app launches instead of crashing.
                print("[PantryLink] On-disk store failed (\(error)); falling back to in-memory.")
                let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                if let container = try? ModelContainer(for: schema, configurations: [memory]) {
                    return container
                }
                fatalError("Unable to build PantryLink ModelContainer: \(error)")
            }
        }
    }

    /// Convenience factory: container + store + repository, wired together.
    /// Mirrors MainActivity's setup (AppDatabase → dao → syncManager → repository).
    @MainActor
    static func makeStack(
        inMemory: Bool = false,
        sync: PantrySyncManager = NoOpSyncManager()
    ) -> (container: ModelContainer, store: PantryLinkStore, repository: PantryLinkRepository) {
        let container = makeContainer(inMemory: inMemory)
        let store = PantryLinkStore(modelContainer: container)
        let repository = PantryLinkRepository(store: store, sync: sync)
        return (container, store, repository)
    }
}
