//
//  NotificationService.swift
//  Monee
//
//  Fires the "already saved — tap to fix" confirmation notification. No notification
//  actions: a single tap is the only interaction. ReceiptCaptureService has already saved
//  the Transaction by the time this fires, so there's no "Save" action to offer.
//

import Foundation
import UserNotifications

enum NotificationUserInfoKey {
    static let transactionID = "transactionID"
}

enum NotificationCategory {
    static let transactionLogged = "TRANSACTION_LOGGED"
}

enum NotificationService {
    /// Registers the notification category. Call defensively at the start of every entry
    /// point (Action Button intent, Share Extension) — a background-launched process may
    /// skip the main app's normal init path, and categories must be registered before a
    /// notification using them can post.
    static func configure() {
        let category = UNNotificationCategory(
            identifier: NotificationCategory.transactionLogged,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func scheduleCaptureNotification(for transaction: Transaction) {
        let content = UNMutableNotificationContent()
        content.title = "Logged"
        content.body = "\(transaction.title) — \(transaction.amount.idrFormatted)"
        content.categoryIdentifier = NotificationCategory.transactionLogged
        content.userInfo = [NotificationUserInfoKey.transactionID: transaction.id.uuidString]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
