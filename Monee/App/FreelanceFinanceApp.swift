//
//  FreelanceFinanceApp.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 27/06/26.
//  Updated 02/07/26 — swapped scenePhase .onChange for .onReceive on
//  UIApplication.didBecomeActiveNotification. onChange's overload set was resolving
//  inconsistently on this SDK (1-arg/2-arg/0-arg errors on identical code across
//  attempts) — NotificationCenter has one stable signature and sidesteps it entirely.
//

import SwiftUI
import SwiftData
import UIKit

@main struct FreelanceFinanceApp: App {
    let container = SwiftDataService.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppContainer.shared)
                .onOpenURL { url in
                    AppContainer.shared.handle(url: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    AppContainer.shared.checkForPendingReceipt()
                }
        }
        .modelContainer(container)
    }
}
