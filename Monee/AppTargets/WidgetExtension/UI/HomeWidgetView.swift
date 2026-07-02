//
//  HomeWidgetView.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


import SwiftUI
import WidgetKit
import AppIntents

/// ⚠️ UI PLACEHOLDER — layout/icon/colors are functional-only, proving the
/// deep-link plumbing works end to end. UI team: restyle freely.
struct HomeWidgetView: View {
    var entry: HomeWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.green)
                Text("Monee").font(.headline)
                Spacer()
            }

            Spacer()

            Button(intent: QuickEntryIntent()) {
                Label("Quick Entry", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .widgetURL(DeepLink.quickEntry.url) // fallback tap target for the rest of the widget
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

#Preview(as: .systemSmall) {
    HomeWidget()
} timeline: {
    HomeWidgetEntry(date: .now)
}
