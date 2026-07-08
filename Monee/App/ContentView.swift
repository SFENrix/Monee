//
//  ContentView.swift
//  FreelanceFinance
//
//  App root: four-tab shell (Tracker / Summary / Profile / AI Buddy). The old
//  single-screen Dashboard this file used to hold was retired once TrackerView +
//  ProfileView (real, design-provided views) replaced it.
//
//  Updated 07/07/26 — added a non-dismissable fullScreenCover showing OnboardingView
//  until UserProfile.hasCompletedOnboarding is true, synced into AppContainer on launch
//  so the same in-memory flag OnboardingView already flips on completion works without
//  a relaunch.
//
//  Updated 08/07/26 — merged with origin/gwen's Dashboard tab (emergency fund +
//  expense/income donut chart) and retired the separate placeholder Summary tab
//  that briefly duplicated it — DashboardView is now rewired to UserProfile's
//  emergency fund fields and the real TransactionCategory instead of its own
//  disconnected AppStorage/keyword-matching version.
//
//  Updated 08/07/26 — the surviving tab (backed by DashboardView) is user-facing
//  "Summary", not "Dashboard" — DashboardView is an internal name only, kept as-is
//  to avoid an unnecessary rename/file-move churn.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case tracker
    case summary
    case profile
    case aiChat
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .aiChat
    @Environment(AppContainer.self) private var appContainer

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Tracker", systemImage: "wallet.bifold.fill", value: AppTab.tracker) {
                TrackerView()
            }

            Tab("Summary", systemImage: "chart.pie.fill", value: AppTab.summary) {
                DashboardView()
            }

            Tab("Profile", systemImage: "person.fill", value: AppTab.profile) {
                ProfileView()
            }


            Tab(value: AppTab.aiChat, role: .search) {
                AIChatView()
            } label: {
                Label("Monee",image: "buntel")
            }
        }
        .task {
            appContainer.isUserOnboarded = UserProfile.hasCompletedOnboarding
        }
        .fullScreenCover(isPresented: Binding(
            get: { !appContainer.isUserOnboarded },
            set: { _ in }
        )) {
            OnboardingView()
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
