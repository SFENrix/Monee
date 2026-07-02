//
//  DeepLink.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  DeepLink.swift
//  Monee
//
//  Core/Sharing/DeepLink.swift
//
//  Every route an external surface (Widget, Share Extension) can push the app to.
//  Add cases here first, wire handling in ContentView second — keeps routing in
//  one place instead of scattered URL string checks.
//

import Foundation

enum DeepLink: Equatable {
    case quickEntry
    case pendingReceipt   // ShareExtension dropped an image, go process it

    /// moneeapp://quickEntry  /  moneeapp://pendingReceipt
    var url: URL {
        switch self {
        case .quickEntry: return URL(string: "moneeapp://quickEntry")!
        case .pendingReceipt: return URL(string: "moneeapp://pendingReceipt")!
        }
    }

    init?(url: URL) {
        switch url.host {
        case "quickEntry": self = .quickEntry
        case "pendingReceipt": self = .pendingReceipt
        default: return nil
        }
    }
}