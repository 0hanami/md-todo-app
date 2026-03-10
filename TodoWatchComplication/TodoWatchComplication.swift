//
//  TodoWatchComplication.swift
//  TodoWatchComplication
//
//  watchOS文字盤用Complication（Widget Extension）
//  タップでTodoWatchアプリを起動する
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
        // 静的表示のみのため更新不要
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
    }
}

struct CornerComplicationView: View {
    var body: some View {
        Image(systemName: "checklist")
            .font(.title3)
            .foregroundColor(.green)
            .widgetLabel {
                Text("タスク追加")
            }
    }
}

struct InlineComplicationView: View {
    var body: some View {
        Label("タスク追加", systemImage: "plus.circle")
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
        }
        .configurationDisplayName("タスク追加")
        .description("タップしてタスクを音声入力")
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
