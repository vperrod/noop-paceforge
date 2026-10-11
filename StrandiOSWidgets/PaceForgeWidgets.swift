import WidgetKit
import SwiftUI
import AppIntents
import StrandDesign

// PaceForge widgets. They read only the PFSummary file the app writes into the App Group after each
// PaceForge fetch; the extension has no network access and no Keychain. Tapping opens PaceForge > Today.

struct PFEntry: TimelineEntry {
    let date: Date
    let summary: PFSummary?
    let stale: Bool
}

struct PFProvider: TimelineProvider {
    func placeholder(in context: Context) -> PFEntry {
        PFEntry(date: Date(), summary: .sample, stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PFEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PFEntry>) -> Void) {
        // The app reloads timelines after every fetch; this is only the safety net for a closed app,
        // and it also rolls the day-based "stale" check forward.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> PFEntry {
        let summary = PFSummary.load()
        return PFEntry(date: Date(), summary: summary, stale: summary?.isStale() ?? true)
    }
}

extension PFSummary {
    /// Obvious sample data for the widget gallery only.
    static var sample: PFSummary {
        var s = PFSummary(updated: Date(), date: PFSummary.dayString())
        s.sessions = [PFSummary.Session(name: "Intervals", sport: "run", detail: "8.0 km \u{00B7} 55 min",
                                        target: "4:10\u{2013}4:20/km", mainSet: "4 \u{00D7} 1 km @ 4:10/km", done: false)]
        s.recovery = 81; s.strain = 11.4; s.strainLow = 12; s.strainHigh = 15; s.sleep = 84
        s.sleepHours = "7h20"; s.sleepNeed = "8h00"; s.hrv = 39; s.restingHr = 51; s.acwr = 1.1
        s.briefHeadline = "A green recovery morning, so the planned intervals are on."
        s.race = PFSummary.Race(name: "Example 10K", date: PFSummary.dayString(Date().addingTimeInterval(21 * 86400)), days: 21)
        return s
    }
}

private let paceForgeURL = URL(string: "noop://paceforge")

struct PaceForgeTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.today, provider: PFProvider()) { entry in
            PFTodayEntryView(entry: entry)
                .widgetURL(paceForgeURL)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge Today")
        .description("Today's workout, your PaceForge recovery, strain and sleep, key metrics and your next race.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct PFTodayEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PFEntry

    var body: some View {
        PFTodayWidgetFace(summary: entry.summary, stale: entry.stale, family: family)
    }
}

struct PaceForgeSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.session, provider: PFProvider()) { entry in
            PFSessionEntryView(entry: entry)
                .widgetURL(paceForgeURL)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge session")
        .description("Today's session with your PaceForge recovery. Also on the Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct PFSessionEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PFEntry

    var body: some View {
        PFSessionWidgetFace(summary: entry.summary, stale: entry.stale, family: family)
    }
}

struct PaceForgeRaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.race, provider: PFProvider()) { entry in
            PFRaceEntryView(entry: entry)
                .widgetURL(paceForgeURL)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge race")
        .description("Days to your next race.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct PFRaceEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PFEntry

    var body: some View {
        PFRaceWidgetFace(summary: entry.summary, stale: entry.stale, family: family)
    }
}

struct PaceForgeRecoveryGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.recoveryGauge, provider: PFProvider()) { entry in
            PFGaugeWidgetFace(kind: .recovery, summary: entry.summary, stale: entry.stale)
                .widgetURL(paceForgeURL)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("PaceForge recovery")
        .description("Your PaceForge recovery on the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct PaceForgeStrainGaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.strainGauge, provider: PFProvider()) { entry in
            PFGaugeWidgetFace(kind: .strain, summary: entry.summary, stale: entry.stale)
                .widgetURL(paceForgeURL)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("PaceForge strain")
        .description("Today's strain against your target band on the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// iOS 18 control: sits in Control Center or on the Lock Screen and opens PaceForge > Today.
@available(iOS 18.0, *)
struct PaceForgeTodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "PaceForgeTodayControl") {
            ControlWidgetButton(action: OpenPaceForgeTodayIntent()) {
                Label("PaceForge Today", systemImage: "figure.run")
            }
        }
        .displayName("PaceForge Today")
        .description("Open NOOP on PaceForge Today.")
    }
}
