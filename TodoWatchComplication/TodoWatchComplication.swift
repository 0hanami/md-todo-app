//
//  TodoWatchComplication.swift
//  TodoWatchComplication
//
//  WidgetKit-based watch face complication.
//  Taps open the TodoWatch app for quick task entry.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
}

// MARK: - Timeline Provider

struct SimpleProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date())
        // Static display only; no periodic refresh needed
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Complication Views

struct CircularComplicationView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
        }
        .widgetURL(URL(string: "mdtodo://add"))
    }
}

struct CornerComplicationView: View {
    var body: some View {
        Image(systemName: "checklist")
            .font(.title3)
            .foregroundColor(.green)
            .widgetLabel {
                Text("Add Task")
            }
            .widgetURL(URL(string: "mdtodo://add"))
    }
}

struct InlineComplicationView: View {
    var body: some View {
        Label("Add Task", systemImage: "plus.circle")
            .widgetURL(URL(string: "mdtodo://add"))
    }
}

// MARK: - Widget

struct TodoWatchComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SimpleProvider.Entry

    var body: some View {
        switch family {
        case .accessoryCorner:
            CornerComplicationView()
        case .accessoryInline:
            InlineComplicationView()
        default:
            CircularComplicationView()
        }
    }
}

struct TodoWatchComplication: Widget {
    let kind = "TodoWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SimpleProvider()
        ) { entry in
            TodoWatchComplicationEntryView(entry: entry)
                .widgetURL(URL(string: "mdtodo://add"))
        }
        .configurationDisplayName("Add Task")
        .description("Tap to add a task via voice input")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - Widget Bundle (Entry Point)

@main
struct TodoWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        TodoWatchComplication()
    }
}
