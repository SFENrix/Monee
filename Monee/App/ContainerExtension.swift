//
//  AppContainer+Notifications.swift
//  Monee
//
//  Created by Rio Ferdinand on 03/07/26.
//
//  Split out of AppContainer.swift on purpose — this file references
//  PendingReceiptStore, RegexParser, and Transaction, none of which WidgetExtension
//  needs or should carry. Main app target membership ONLY. `didReceive` is an optional
//  UNUserNotificationCenterDelegate requirement, so adding it here (separate from
//  `willPresent` in the core file) is valid Swift — no conformance is split or broken.
//

import Foundation
import SwiftData
import UserNotifications

extension AppContainer {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let receiptID = response.notification.request.content.userInfo["receiptID"] as? String

        switch response.actionIdentifier {
        case NotificationAction.save:
            if let receiptID { saveReceiptInBackground(id: receiptID) }
        case NotificationAction.dismiss:
            if let receiptID { PendingReceiptStore.remove(id: receiptID) }
        default:
            DispatchQueue.main.async {
                self.pendingRoute = .pendingReceipt(id: receiptID)
            }
        }

        completionHandler()
    }

    /// Saves directly from the notification, no app UI shown. Only offered by
    /// NotificationService's "complete" category, so the amount guard below should
    /// never actually fail in practice — kept as a safety net, not the expected path.
    fileprivate func saveReceiptInBackground(id: String) {
        guard let container = modelContainer,
              let entry = PendingReceiptStore.entry(id: id) else { return }

        let parsed = RegexParser.parse(entry.rawText)
        guard let amount = parsed.amount else { return }

        let context = ModelContext(container)
        let transaction = Transaction(
            title: parsed.keyword?.capitalized ?? "Receipt",
            amount: amount,
            date: parsed.date ?? Date(),
            category: parsed.category,
            source: .ocr,
            rawKeyword: parsed.keyword
        )
        context.insert(transaction)
        try? context.save()

        PendingReceiptStore.remove(id: id)
        notifySaved(title: transaction.title, amount: amount)
    }

    /// Quick confirmation that Save actually did something — there's no UI shown
    /// otherwise, and a silent success is indistinguishable from a silent failure.
    fileprivate func notifySaved(title: String, amount: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Saved"
        content.body = "\(title) — $\(String(format: "%.2f", amount)) logged to Monee."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
