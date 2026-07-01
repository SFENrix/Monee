//
//  FreelanceFinanceApp.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 27/06/26.
//

import SwiftUI
import SwiftData

@main
struct FreelanceFinanceApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Transaction.self,
            ChatSession.self
        ])
    }
}
