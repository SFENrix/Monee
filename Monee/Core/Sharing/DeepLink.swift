//
//  DeepLink.swift
//  Monee
//
//  Core/Sharing/DeepLink.swift
//
//  Updated 03/07/26 — removed .pendingReceipt. The Share Extension/notification-based
//  receipt handoff is retired (unreliable on real-device testing for a 2-day sprint).
//  Receipt scanning is now entirely in-app via ReceiptConfirmationView's PhotosPicker.
//  Only remaining route is the Widget's Quick Entry tap.
//

import Foundation

enum DeepLink: Equatable {
    case quickEntry

    var url: URL {
        switch self {
        case .quickEntry:
            return URL(string: "moneeapp://quickEntry")!
        }
    }

    init?(url: URL) {
        switch url.host {
        case "quickEntry":
            self = .quickEntry
        default:
            return nil
        }
    }
}
