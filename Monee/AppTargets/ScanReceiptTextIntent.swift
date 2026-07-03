//
//  ScanReceiptTextIntent.swift
//  Monee
//
//  Created by Rio Ferdinand on 03/07/26.
//
//  Entry point for the Action Button flow. Lives in the MAIN APP target, not
//  WidgetExtension — unlike QuickEntryIntent (which the widget UI calls directly),
//  nothing inside the app calls this one; it's invoked externally by a user-built
//  Shortcut. Keeping it in the main target means it already sees RegexParser,
//  PendingReceiptStore, NotificationService, AppGroup, Transaction — no extra target
//  membership wiring needed for this file specifically.
//
//  Intended Shortcut (built once, by hand, in the Shortcuts app):
//    1. Take Screenshot
//    2. Extract Text from Image  (Shortcuts' built-in Live Text OCR action)
//    3. Run App Intent → Monee → "Scan Receipt Text", with Captured Text ← step 2's output
//  Then: Settings → Action Button → Shortcut → pick the above.
//
//  `openAppWhenRun = false` is the whole point — capturing a transaction should never
//  interrupt whatever the user was looking at when they pressed the button.
//

import AppIntents
import Foundation

struct ScanReceiptTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Receipt Text"
    static var description = IntentDescription(
        "Parses on-screen receipt or payment text (captured via Shortcuts) and stages it as a transaction."
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

        let parsed = RegexParser.parse(trimmed)
        let entry = PendingReceiptStore.add(rawText: trimmed, parsed: parsed, source: .actionButton)
        NotificationService.scheduleReceiptNotification(for: entry)

        if let amount = entry.amount {
            return .result(dialog: "Found $\(String(format: "%.2f", amount)) — check the notification to confirm.")
        } else {
            return .result(dialog: "Captured the text, but couldn't find an amount — check the notification to fill it in.")
        }
    }
}

// MARK: - Optional: Siri / Spotlight discoverability
//
// Only ONE type per app target may conform to AppShortcutsProvider — if you already
// have one elsewhere, merge this phrase into it instead of adding a second conformance.
// This isn't required for the Action Button flow itself (any AppIntent is automatically
// runnable from a Shortcut); it just adds a Siri phrase and Spotlight suggestion on top.
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
