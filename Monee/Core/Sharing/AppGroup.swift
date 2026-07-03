//
//  AppGroup.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Shared constants so the main app, ShareExtension, and WidgetExtension can all
//  talk to the same sandboxed container. Add this file to ALL THREE targets.
//
//  ⚠️ Replace the identifier below with whatever you register in
//  Signing & Capabilities → App Groups. Must match EXACTLY across all 3 targets.
//
//  Updated 03/07/26 — retired the single-slot `hasPendingReceiptImage` flag. Every
//  capture (Action Button text, Share Extension text OR image) now goes through
//  PendingReceiptStore's id-addressable queue, so image storage is keyed by entry id
//  instead of one overwriteable file. Fixes a real compile break: ContentView and
//  ShareViewController were still referencing a `hasPendingReceipt` key that no longer
//  existed after the queue-based store landed.
//

import Foundation

enum AppGroup {
    static let identifier = "group.com.rioferdinand.freelancefinance"

    static var defaults: UserDefaults {
        guard let suite = UserDefaults(suiteName: identifier) else {
            fatalError("App Group '\(identifier)' not configured — check Signing & Capabilities on every target.")
        }
        return suite
    }

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            fatalError("App Group container unavailable for '\(identifier)'.")
        }
        return url
    }

    /// Per-entry image cache — keyed by PendingReceiptEntry.id so an Action Button
    /// capture and a Share Extension capture can never collide, and multiple pending
    /// entries can coexist safely.
    static func pendingReceiptImageURL(id: String) -> URL {
        containerURL.appendingPathComponent("pending_receipt_\(id).jpg")
    }
}

enum AppGroupKey {
    /// JSON-encoded [PendingReceiptEntry], managed by PendingReceiptStore. Single
    /// source of truth for every in-flight capture regardless of origin.
    static let pendingReceiptTexts = "pendingReceiptTexts"
}
