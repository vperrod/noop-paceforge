import WidgetKit
import SwiftUI
import StrandDesign

// "Effort target" widget: today's Effort against the OPTIMAL band, small on the Home Screen and circular on
// the Lock Screen. It reads only the WidgetSnapshot the app writes into the App Group; the extension has no
// database, network or Keychain. A snapshot from another day, or older than six hours, shows the
// open-NOOP face instead of yesterday's band.

struct EffortTargetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let stale: Bool
}

struct EffortTargetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EffortTargetEntry {
        EffortTargetEntry(date: Date(), snapshot: .effortTargetSample, stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (EffortTargetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EffortTargetEntry>) -> Void) {
        // The app reloads widgets after each publish; this is the safety net for a closed app and it rolls
        // the freshness check forward.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> EffortTargetEntry {
        let snapshot = WidgetSnapshot.load()
        return EffortTargetEntry(date: Date(), snapshot: snapshot, stale: !(snapshot?.effortTargetIsFresh() ?? false))
    }
}

struct EffortTargetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EffortTargetEntry

    var body: some View {
        EffortTargetWidgetFace(snapshot: entry.snapshot, stale: entry.stale, family: family)
    }
}

struct EffortTargetWidget: Widget {
    static let kind = "EffortTargetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: EffortTargetProvider()) { entry in
            EffortTargetWidgetView(entry: entry)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("Effort target")
        .description("Today's Effort against the range your Charge suggests.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
