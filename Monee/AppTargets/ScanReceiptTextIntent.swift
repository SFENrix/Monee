//
//  ScanReceiptTextIntent.swift
//  Monee
//
//  Entry point for the Action Button flow. Lives in the MAIN APP target, not
//  WidgetExtension — unlike QuickEntryIntent (which the widget UI calls directly), nothing
//  inside the app calls this one; it's invoked externally by a user-built Shortcut.
//
//  Intended Shortcut (built once, by hand, in the Shortcuts app):
//    1. Take Screenshot
//    2. Extract Text from Image  (Shortcuts' built-in Live Text OCR action)
//    3. Run App Intent → Monee → "Scan Receipt Text", with Captured Text ← step 2's output
//  Then: Settings → Action Button → Shortcut → pick the above.
//
//  `openAppWhenRun = false` is the whole point — capturing a transaction should never
//  interrupt whatever the user was looking at when they pressed the button. This intent's
//  only job is to hand captured text to ReceiptCaptureService; everything else (saving,
//  notifying, editing) happens there and in the app proper.
//

import AppIntents
import Foundation

struct ScanReceiptTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Receipt Text"
    static var description = IntentDescription(
        "Parses on-screen receipt or payment text (captured via Shortcuts) and logs it as a transaction."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Captured Text")
    var rawText: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Defensive — a background-launched intent may skip the app's normal init path,
        // and categories must be registered before a notification using them can post.
        NotificationService.configure()

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "I didn't get any text to scan.")
        }

        switch ReceiptCaptureService.capture(rawText: trimmed) {
        case .saved(let transaction):
            return .result(dialog: "Logged \(transaction.amount.idrFormatted) — check the notification to fix anything.")
        case .amountNotFound:
            return .result(dialog: "Captured the text, but couldn't find an amount — nothing was saved.")
        }
    }
}

// MARK: - Optional: Siri / Spotlight discoverability
//
// Only ONE type per app target may conform to AppShortcutsProvider — if you already
// have one elsewhere, merge this phrase into it instead of adding a second conformance.
struct ScanReceiptShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanReceiptTextIntent(),
            phrases: ["Scan receipt with \(.applicationName)"],
            shortTitle: "Scan Receipt",
            systemImageName: "text.viewfinder"
        )
    }
}
