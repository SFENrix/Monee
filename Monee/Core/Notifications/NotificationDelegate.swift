//
//  NotificationDelegate.swift
//  Monee
//
//  Created by Rio Ferdinand on 03/07/26.
//
//  Handles taps on the receipt notification's actions. This is the piece that makes
//  "Save" actually work without opening the app: because SAVE_RECEIPT has no
//  `.foreground` option (see NotificationCategory.configure), iOS calls
//  `didReceive response:` directly — launching the app briefly in the background if it
//  isn't already running, with no UI shown. EDIT_RECEIPT still has `.foreground`, so
//  that one brings the app forward and routes through the normal DeepLink flow.
//
//  Registered via AppDelegate (`UNUserNotificationCenter.current().delegate = ...`) —
//  SwiftUI's App protocol has no direct hook for this.
//

import Foundation
import SwiftData
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let id = response.notification.request.content.userInfo[NotificationUserInfoKey.pendingReceiptID] as? String else {
            completionHandler()
            return
        }

        Task { @MainActor in
            switch response.actionIdentifier {
            case NotificationAction.save:
                Self.saveTransaction(id: id)
                PendingReceiptStore.remove(id: id)

            case NotificationAction.dismiss:
                PendingReceiptStore.remove(id: id)

            case NotificationAction.edit:
                // .foreground brings the app up; ContentView picks up pendingRoute
                // once it's actually visible and shows ReceiptConfirmationView prefilled.
                AppContainer.shared.pendingRoute = .pendingReceipt(id: id)

            default:
                break
            }
            completionHandler()
        }
    }

    /// Also show the banner if a capture happens to complete while the app is already
    /// in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Writes the Transaction directly — no QuickEntryViewModel involved, since there's
    /// no form on screen to own that state. Uses a fresh ModelContext on the same
    /// on-disk store the main app uses (SwiftDataService.makeContainer() always points
    /// at the same default location), which is what lets this work even when the app
    /// process was launched fresh just to handle this notification tap.
    @MainActor
    private static func saveTransaction(id: String) {
        guard let entry = PendingReceiptStore.entry(id: id), let amount = entry.amount else { return }

        let context = ModelContext(SwiftDataService.makeContainer())
        let transaction = Transaction(
            title: entry.merchant ?? "Receipt",
            amount: amount,
            date: entry.date ?? entry.capturedAt,
            category: entry.isIncome ? .income : entry.category,
            source: .ocr,
            rawKeyword: entry.merchant
        )
        context.insert(transaction)
        try? context.save()
    }
}
