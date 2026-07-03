//
//  FreelanceFinanceApp.swift
//  FreelanceFinance
//
//  Updated 03/07/26 — removed the scenePhase foreground check. It existed only to catch
//  a pending receipt the Share Extension handoff missed; that flow is retired.
//

import SwiftUI
import SwiftData
import UserNotifications

@main struct FreelanceFinanceApp: App {
    let container = SwiftDataService.makeContainer()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppContainer.shared)
                .onOpenURL { url in
                    AppContainer.shared.handle(url: url)
                }
        }
        .modelContainer(container)
    }
}
