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
//    2. Run App Intent → Monee → "Scan Receipt Text"
//  Then: Settings → Action Button → Shortcut → pick the above. Nothing to configure on
//  the second step — no parameter to bind.
//
//  Takes NO parameters on purpose: Shortcuts has no way to bind a previous step's output
//  to a file/image-typed custom App Intent parameter (it only offers a manual "Choose
//  File" picker for those — confirmed dead end, not a configuration mistake). So instead
//  of receiving the screenshot as input, this intent fetches the most recently taken
//  screenshot itself via ScreenshotFetcher (Photos framework) and runs OCR on it with
//  VisionOCRService — the same .accurate + language-correction pipeline the Share
//  Extension and manual capture use. Requires Photo Library read access
//  (NSPhotoLibraryUsageDescription); permission is requested at app launch
//  (FreelanceFinanceApp.init()) so it's already resolved by the time this runs.
//
//  `openAppWhenRun = false` is the whole point — capturing a transaction should never
//  interrupt whatever the user was looking at when they pressed the button. This intent's
//  only job is to hand captured text to ReceiptCaptureService; everything else (saving,
//  notifying, editing) happens there and in the app proper.
//

import AppIntents
import Foundation
import SwiftUI

struct ScanReceiptTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Receipt Text"
    static var description = IntentDescription(
        "Reads your most recent screenshot and logs it as a transaction."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        // Defensive — a background-launched intent may skip the app's normal init path,
        // and categories must be registered before a notification using them can post.
        NotificationService.configure()

        guard let screenshot = await ScreenshotFetcher.fetchMostRecent() else {
            return .result(view: ReceiptConfirmationSnippetView(
                state: .error("Couldn't access your most recent screenshot — check Photo Library access in Settings.")
            ))
        }

        let rawText = (try? await VisionOCRService.recognizeText(from: screenshot)) ?? ""
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(view: ReceiptConfirmationSnippetView(
                state: .error("I couldn't read any text from that screenshot.")
            ))
        }

        switch ReceiptCaptureService.stage(rawText: trimmed) {
        case .needsConfirmation(let parsed):
            return .result(view: ReceiptConfirmationSnippetView(
                state: .confirming(
                    title: parsed.suggestedTitle,
                    amount: parsed.amount ?? 0,
                    date: parsed.date ?? Date(),
                    category: parsed.category,
                    rawKeyword: parsed.keyword
                )
            ))
        case .amountNotFound:
            return .result(view: ReceiptConfirmationSnippetView(
                state: .error("Read the screenshot, but couldn't find an amount — nothing was saved.")
            ))
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
