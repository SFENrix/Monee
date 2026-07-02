//
//  QuickEntryIntent.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


import AppIntents

struct QuickEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Entry"
    static var description = IntentDescription("Opens Monee straight into the quick-entry form.")

    /// The key flag — launches/foregrounds the host app and runs perform()
    /// inside the APP's process, not the widget extension's.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppContainer.shared.pendingRoute = .quickEntry
        return .result()
    }
}