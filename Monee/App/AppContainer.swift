//
//  AppContainer.swift
//  Monee
//
//  Created by Rio Ferdinand on 01/07/26.
//  Updated 02/07/26 — added checkForPendingReceipt() directly here instead of a
//  separate file. This type is already shared between Main App and Widget Extension
//  (QuickEntryIntent needs it), so consolidating avoids a second target-membership
//  checkbox to get wrong. AppGroup.swift now also needs Widget Extension membership
//  as a result — see note there.
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

    /// Fallback for when the Share Extension's handoff URL didn't open the app
    /// (flaky on some iOS versions/first-run permission prompts). Call this on
    /// every foreground so a saved-but-unrouted receipt still gets picked up.
    func checkForPendingReceipt() {
        guard pendingRoute == nil else { return } // don't clobber an active deep link
        if AppGroup.defaults.bool(forKey: AppGroupKey.hasPendingReceipt) {
            pendingRoute = .pendingReceipt
        }
    }
}
