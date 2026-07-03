//
//  WidgetExtensionBundle.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


import WidgetKit
import SwiftUI

@main
struct WidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        HomeWidget()
    }
}

struct HomeWidget: Widget {
    let kind: String = "HomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeWidgetProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Monee Quick Add")
        .description("Jump straight into logging an expense.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeWidgetEntry: TimelineEntry {
    let date: Date
}

struct HomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeWidgetEntry { HomeWidgetEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
        completion(HomeWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        // Static content — nothing here depends on live data yet, so no refresh
        // policy needed. Revisit if we add a "this month's spend" figure later.
        completion(Timeline(entries: [HomeWidgetEntry(date: .now)], policy: .never))
    }
}
