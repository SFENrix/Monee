//
//  AppContainer.swift
//  Monee
//
//  Updated 03/07/26 — removed checkForPendingReceipt(). pendingRoute now only ever
//  carries .quickEntry.
//

import Foundation
import Observation

@Observable
final class AppContainer {
    static let shared = AppContainer()

    var isUserOnboarded: Bool = false

    /// Set when the app opens via a deep link (currently: Widget's Quick Entry tap).
    /// ContentView observes this, reacts, then clears it.
    var pendingRoute: DeepLink?

    private init() {}

    func handle(url: URL) {
        guard let route = DeepLink(url: url) else { return }
        pendingRoute = route
    }
}
