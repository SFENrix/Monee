//
//  PendingReceipt.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  AppContainer+PendingReceipt.swift
//  Monee
//
//  Main App target ONLY — deliberately kept out of Widget Extension. AppContainer.swift
//  itself is shared with the widget (for QuickEntryIntent), but this extension needs
//  AppGroup.swift, which the widget doesn't otherwise depend on. Splitting it into its
//  own file keeps the widget target's dependency surface minimal.
//

import Foundation

extension AppContainer {
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