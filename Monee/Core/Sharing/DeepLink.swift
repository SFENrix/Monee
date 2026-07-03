//
//  DeepLink.swift
//  Monee
//
//  Core/Sharing/DeepLink.swift
//
//  .quickEntry: Widget's Quick Entry tap. .editTransaction: tapping the "Logged" notification
//  after an Action Button / Share Extension capture — routes to editing that already-saved
//  Transaction (see NotificationDelegate + ReceiptCaptureService).
//

import Foundation

enum DeepLink: Equatable {
    case quickEntry
    case editTransaction(id: UUID)

    var url: URL {
        switch self {
        case .quickEntry:
            return URL(string: "moneeapp://quickEntry")!
        case .editTransaction(let id):
            return URL(string: "moneeapp://editTransaction?id=\(id.uuidString)")!
        }
    }

    init?(url: URL) {
        switch url.host {
        case "quickEntry":
            self = .quickEntry
        case "editTransaction":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let id = UUID(uuidString: idString) else {
                return nil
            }
            self = .editTransaction(id: id)
        default:
            return nil
        }
    }
}
