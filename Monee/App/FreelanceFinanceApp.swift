//
//  FreelanceFinanceApp.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 27/06/26.
//

import SwiftUI
import SwiftData

@main struct FreelanceFinanceApp: App {
    let container = SwiftDataService.makeContainer()

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

