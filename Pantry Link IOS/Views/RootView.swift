//
//  RootView.swift
//  Pantry Link IOS
//
//  App entry surface: gates between the auth screen and the (authenticated) home,
//  and hosts the global toast + simulated-push overlays and the welcome-rewards sheet —
//  the SwiftUI equivalents of PantryLinkAppScreen's top-level scaffolding.
//

import SwiftUI

struct RootView: View {
    @State private var viewModel: PantryLinkViewModel
    @State private var sync: FirestorePantrySync?

    init() {
        let container = PantryPersistence.makeContainer()
        let store = PantryLinkStore(modelContainer: container)

        // Live Firestore sync when Firebase is configured; otherwise local-only.
        let sync: PantrySyncManager = PantryServiceFactory.isFirebaseAvailable
            ? FirestorePantrySync(store: store)
            : NoOpSyncManager()
        let repository = PantryLinkRepository(store: store, sync: sync)

        let vm = PantryLinkViewModel(
            repository: repository,
            auth: PantryServiceFactory.auth(),
            remoteProfile: PantryServiceFactory.profile(),
            diagnosticsProbe: PantryServiceFactory.diagnostics()
        )
        _viewModel = State(initialValue: vm)
        _sync = State(initialValue: sync as? FirestorePantrySync)
    }

    var body: some View {
        ZStack {
            if viewModel.isUserLoggedIn() {
                HomeShell(viewModel: viewModel)
            } else {
                AuthGateView(viewModel: viewModel)
            }

            // Simulated device push (Kotlin: activePushAlert top banner)
            if let alert = viewModel.activePushAlert {
                VStack {
                    PushBanner(text: alert) { viewModel.dismissPushAlert() }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // In-app toast (Kotlin: toastMessage)
            if let toast = viewModel.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .glassEffect(.regular.tint(Color.pantryTextDark.opacity(0.75)), in: .capsule)
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2.5))
                    viewModel.clearToast()
                }
            }
        }
        // (Re)subscribe the Firestore listeners whenever auth state changes — the collection
        // `list` queries run authenticated post sign-in, mirroring remote data (incl. anything
        // the Android app wrote) into the local store. `startListening` removes prior listeners.
        .task(id: viewModel.userSession?.uid ?? "anon") {
            sync?.startListening { [weak viewModel] in
                Task { @MainActor in await viewModel?.refreshAll() }
            }
        }
        .animation(.easeInOut, value: viewModel.toastMessage)
        .animation(.easeInOut, value: viewModel.activePushAlert)
        .sheet(isPresented: Binding(
            get: { viewModel.showWelcomeRewardsDialog },
            set: { if !$0 { viewModel.dismissWelcomeRewardsDialog() } }
        )) {
            WelcomeRewardsView { viewModel.dismissWelcomeRewardsDialog() }
        }
    }
}

// MARK: - Push banner

struct PushBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.badge.fill").foregroundStyle(Color.pantryTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(parts.first ?? text).font(.system(size: 13, weight: .bold))
                if parts.count > 1 {
                    Text(parts[1]).font(.system(size: 11)).foregroundStyle(Color.pantryTextMuted)
                }
            }
            Spacer()
            Button { onDismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                .foregroundStyle(Color.pantryTextMuted)
        }
        .padding(14)
        .pantryGlassCard(cornerRadius: 18)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

// MARK: - Home shell (top bar + role routing)

struct HomeShell: View {
    @Bindable var viewModel: PantryLinkViewModel

    private var isFoodBank: Bool { viewModel.selectedRole == PantryRole.foodBank.rawValue }

    var body: some View {
        // Account type is immutable — routing by the stored role is the lock (a Donor account
        // can never reach the Food Bank workspace or vice-versa). Nav + Sign Out live in each
        // tab's native navigation bar (see workspaceChrome).
        if isFoodBank {
            FoodBankWorkspaceView(viewModel: viewModel)
        } else {
            DonorWorkspaceView(viewModel: viewModel)
        }
    }
}
