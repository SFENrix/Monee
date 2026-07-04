//
//  SwiftDataService.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  SwiftDataService.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Single source of truth for the app's SwiftData schema and ModelContainer setup.
//  When Threshold Savings is greenlit, add JarState.self / Goal.self to `schema` below
//  and nowhere else — everything reading from the container picks it up automatically.
//

import Foundation
import SwiftData

enum SwiftDataService {

    static let schema = Schema([
        Transaction.self,
        ChatSession.self,
        ChatMessage.self
        // JarState.self,  // Threshold Savings — add only once that feature is greenlit
        // Goal.self,      // Threshold Savings — add only once that feature is greenlit
    ])

    /// Production container — persists to disk. Used by the real app.
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(AppGroup.identifier)
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }

    /// In-memory container for #Preview and unit tests — nothing touches disk, nothing
    /// leaks between runs.
    @MainActor static func makePreviewContainer(seeded: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            if seeded {
                seedPreviewData(into: container.mainContext)
            }
            return container
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error.localizedDescription)")
        }
    }

    /// Drops a few sample transactions into a preview container so SwiftUI previews
    /// don't render empty-state UI while we're iterating on the Dashboard.
    private static func seedPreviewData(into context: ModelContext) {
        let samples = [
            Transaction(title: "Adobe Creative Cloud", amount: 54.99, date: .now, category: .software),
            Transaction(title: "Client lunch — Kopi Kenangan", amount: 12.50, date: .now.addingTimeInterval(-86_400), category: .meals),
            Transaction(title: "Grab to client office", amount: 8.20, date: .now.addingTimeInterval(-172_800), category: .travel)
        ]
        samples.forEach { context.insert($0) }
    }
}
