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
//  Updated 08/07/26 — AI tab icon, take 2: dropping `role: .search` (to get
//  the custom "buntel" icon to render) broke the layout worse — instead of a
//  4-item tab bar it collapsed into a single full-width bar. Reverted back to
//  `Tab(role: .search)` with plain `Label("Monee", image: "buntel")`.
//  `role: .search` is doing its job correctly (separate floating circle,
//  correct tab bar layout); the blank/tinted circle is very likely the
//  "buntel" image asset's Render As setting in Assets.xcassets — if it's set
//  to "Template Image" instead of "Default"/"Original Image", the system tab
//  chrome will only draw its alpha shape tinted with the accent color
//  (exactly the flat purple circle we're seeing), and no code-level
//  .renderingMode() modifier reliably overrides that inside this system
//  affordance. Fix on the asset itself: select the "buntel" image set in
//  Assets.xcassets → Attributes inspector → Render As → "Default" (or
//  "Original Image"), not "Template Image".
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
            Tab("Chat", systemImage: "message.fill", value: AppTab.aiChat) {
                AIChatView()
            }
            
            Tab("Tracker", systemImage: "wallet.bifold.fill", value: AppTab.tracker) {
                TrackerView()
            }

            Tab("Summary", systemImage: "chart.pie.fill", value: AppTab.summary) {
                DashboardView()
            }

            Tab("Savings", systemImage: "dollarsign.circle.fill", value: AppTab.profile) {
                SavingsView()
            }

//            Tab(value: AppTab.aiChat, role: .search) {
//                AIChatView()
//            } label: {
//                Label("Chat", systemImage: "message.fill")
//            }
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
