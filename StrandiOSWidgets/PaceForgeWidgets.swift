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
        return PFEntry(date: Date(), summary: summary?.redactedForDisplay(), stale: summary?.isStale() ?? true)
    }
}

extension PFSummary {
    /// Obvious sample data for the widget picker and gallery only. Every newer field is filled too, so no
    /// preview falls back to its "open NOOP" face.
    static var sample: PFSummary {
        var s = PFSummary(updated: Date(), date: PFSummary.dayString())
        s.sessions = [PFSummary.Session(name: "Intervals", sport: "run", detail: "8.0 km \u{00B7} 55 min",
                                        target: "4:10\u{2013}4:20/km", mainSet: "4 \u{00D7} 1 km @ 4:10/km", done: false)]
        s.recovery = 81; s.strain = 11.4; s.strainLow = 12; s.strainHigh = 15; s.sleep = 84
        s.sleepHours = "7h20"; s.sleepNeed = "8h00"; s.hrv = 39; s.restingHr = 51; s.acwr = 1.1
        s.briefHeadline = "A green recovery morning, so the planned intervals are on."
        s.race = PFSummary.Race(name: "Example 10K", date: PFSummary.dayString(Date().addingTimeInterval(21 * 86400)), days: 21)
        return s.fillingSampleGaps()
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

struct PaceForgeWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.week, provider: PFProvider()) { entry in
            PFWeekWidgetFace(summary: entry.summary, stale: entry.stale)
                .widgetURL(URL(string: "noop://paceforge/week"))
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge week")
        .description("Your planned and done sessions this week, and the week's load against its target.")
        .supportedFamilies([.systemMedium])
    }
}

struct PaceForgeSleepHrvWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.sleepHrv, provider: PFProvider()) { entry in
            PFSleepHrvWidgetFace(summary: entry.summary, stale: entry.stale)
                .widgetURL(paceForgeURL)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge sleep and HRV")
        .description("Seven nights of sleep and your HRV against its baseline.")
        .supportedFamilies([.systemMedium])
    }
}

private struct PFLoadEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PFEntry

    var body: some View {
        PFLoadWidgetFace(summary: entry.summary, stale: entry.stale, family: family)
    }
}

struct PaceForgeLoadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.load, provider: PFProvider()) { entry in
            PFLoadEntryView(entry: entry)
                .widgetURL(URL(string: "noop://paceforge/insights"))
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge training load")
        .description("Acute to chronic load ratio against its safe zone. Also on the Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct PFHeartRecoveryEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PFEntry

    var body: some View {
        PFHeartRecoveryWidgetFace(summary: entry.summary, family: family)
    }
}

struct PaceForgeHeartRecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.hrr, provider: PFProvider()) { entry in
            PFHeartRecoveryEntryView(entry: entry)
                .widgetURL(URL(string: "noop://paceforge/week"))
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge heart recovery")
        .description("How far your heart rate fell in the first minute after your latest session. Also on the Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct PaceForgeBodyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PFWidgetKind.body, provider: PFProvider()) { entry in
            PFBodyWidgetFace(summary: entry.summary, stale: entry.stale)
                .widgetURL(URL(string: "noop://paceforge/body"))
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("PaceForge body")
        .description("Your Hume body score, weight and body fat since the last reading.")
        .supportedFamilies([.systemSmall])
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
