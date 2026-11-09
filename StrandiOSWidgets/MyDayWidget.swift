import WidgetKit
import SwiftUI
import StrandDesign

// "My Day" medium widget: the last six hours of heart rate and the next planned session. It reads only the
// MyDaySummary file the app writes into the App Group; the extension has no database, network or Keychain.
// Tapping opens NOOP on My Day.

struct MyDayEntry: TimelineEntry {
    let date: Date
    let summary: MyDaySummary?
    let stale: Bool
}

struct MyDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> MyDayEntry {
        MyDayEntry(date: Date(), summary: .sample, stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MyDayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MyDayEntry>) -> Void) {
        // The app reloads this widget after each refresh; this is the safety net for a closed app and it
        // rolls the "stale" check forward.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> MyDayEntry {
        let summary = MyDaySummary.load()
        return MyDayEntry(date: Date(), summary: summary, stale: summary?.isStale() ?? true)
    }
}

struct MyDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MyDaySummary.widgetKind, provider: MyDayProvider()) { entry in
            MyDayWidgetFace(summary: entry.summary, stale: entry.stale)
                .widgetURL(URL(string: "noop://myday"))
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("My Day")
        .description("The last six hours of heart rate and your next planned session.")
        .supportedFamilies([.systemMedium])
    }
}
