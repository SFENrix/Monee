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
import Photos

@main struct FreelanceFinanceApp: App {
    let container = SwiftDataService.makeContainer()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // Requested here (not lazily inside ScanReceiptTextIntent) because a
        // background-launched App Intent (openAppWhenRun = false) may not be able to
        // present the system permission prompt — by the time the Action Button is used,
        // this should already be resolved.
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppContainer.shared)
                .onOpenURL { url in
                    AppContainer.shared.handle(url: url)
                }
        }
        .modelContainer(container)
    }
}
