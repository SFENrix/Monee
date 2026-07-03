//
//  NotificationDelegate.swift
//  Monee
//
//  Handles taps on the "Logged" notification ReceiptCaptureService fires after an Action
//  Button / Share Extension capture. There's only one interaction: tap to edit — no Save
//  action (already saved) and no Dismiss action (swipe-to-delete in the Tracker list covers
//  discarding a bad capture).
//
//  `shared` exists because UNUserNotificationCenter.delegate is a WEAK reference — an
//  unretained instance would be deallocated immediately and silently stop receiving
//  callbacks. FreelanceFinanceApp.init() assigns `NotificationDelegate.shared` as the
//  delegate, which keeps it alive for the app's lifetime.
//

import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let idString = response.notification.request.content.userInfo[NotificationUserInfoKey.transactionID] as? String,
              let id = UUID(uuidString: idString) else {
            return
        }

        Task { @MainActor in
            AppContainer.shared.pendingRoute = .editTransaction(id: id)
        }
    }

    /// Also show the banner if a capture happens to complete while the app is already in
    /// the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
