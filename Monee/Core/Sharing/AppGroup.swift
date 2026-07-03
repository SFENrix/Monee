//
//  AppGroup.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  AppGroupConfig.swift
//  Monee
//
//  Core/Sharing/AppGroupConfig.swift
//
//  Shared constants so the main app, ShareExtension, and WidgetExtension can all
//  talk to the same sandboxed container. Add this file to ALL THREE targets.
//
//  ⚠️ Replace the identifier below with whatever you register in
//  Signing & Capabilities → App Groups. Must match EXACTLY across all 3 targets.
//

import Foundation

enum AppGroup {
    static let identifier = "group.com.rioferdinand.monee"

    /// Small flags/values (deep-link routing, "pending receipt" flag).
    static var defaults: UserDefaults {
        guard let suite = UserDefaults(suiteName: identifier) else {
            fatalError("App Group '\(identifier)' not configured — check Signing & Capabilities on every target.")
        }
        return suite
    }

    /// Actual files — e.g. the receipt image ShareExtension hands to the main app.
    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            fatalError("App Group container unavailable for '\(identifier)'.")
        }
        return url
    }

    static var pendingReceiptImageURL: URL {
        containerURL.appendingPathComponent("pending_receipt.jpg")
    }
}

enum AppGroupKey {
    static let hasPendingReceipt = "hasPendingReceipt"
    static let pendingReceiptSavedAt = "pendingReceiptSavedAt"
}
