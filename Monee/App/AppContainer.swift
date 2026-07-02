//
//  AppContainer.swift
//  Monee
//
//  Created by Rio Ferdinand on 01/07/26.
//


import Foundation
import Observation

@Observable
final class AppContainer {
    static let shared = AppContainer()

    var isUserOnboarded: Bool = false

    /// Set when the app opens via a deep link (Widget tap, Share Extension handoff).
    /// ContentView observes this, reacts, then clears it.
    var pendingRoute: DeepLink?

    private init() {}

    func handle(url: URL) {
        guard let route = DeepLink(url: url) else { return }
        pendingRoute = route
    }
}
