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
//  Updated 07/07/26 — added the Summary tab (placeholder UI) between Tracker and
//  Profile, surfacing the new Spare Money + emergency fund + expense pie chart.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case tracker
    case summary
    case profile
    case dashboard
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
            
            Tab("Dashboard", systemImage: "chart.pie.fill", value: AppTab.dashboard){
                DashboardView()
            }

            Tab("Summary", systemImage: "chart.pie.fill", value: AppTab.summary) {
                SummaryView()
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
