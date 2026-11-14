#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Health: the fourth tab
//
// Chips at the top and ONE chip mounted below them: Day (My Day), Sleep (with rows to Alarms and Rhythm), Recovery (the readiness
// readings and the Charge, Effort and Rest details), Body (the scale screen and the Lab Book), Vitals (Health, Stress and Healthspan),
// Journal (the journal and Journal impact) and Trends (the Trends screen with Compare and the Metric Explorer). Each chip is the content
// of a screen that exists elsewhere, drawn in this screen's scroll view. NOOP's and PaceForge's numbers are never merged.

enum HealthChip: String, CaseIterable, Identifiable {
    case day, sleep, recovery, body, vitals, journal, trends

    /// The chip on show, shared with the shell so a link can land on a chip. Kept between launches.
    static let storageKey = "noop.health.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .sleep: return "Sleep"
        case .recovery: return "Recovery"
        case .body: return "Body"
        case .vitals: return "Vitals"
        case .journal: return "Journal"
        case .trends: return "Trends"
        }
    }
}

/// The Health tab's root.
struct HealthHostView: View {
    @AppStorage(HealthChip.storageKey) private var chipRaw = HealthChip.day.rawValue

    private var chip: HealthChip { HealthChip(rawValue: chipRaw) ?? .day }

    private var selection: Binding<HealthChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip health.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Health",
                       onRefresh: { await PFUnified.model.refresh() }, lazy: true, topBackground: liquidScaffoldSky()) {
            HealthColumn(selection: selection)
        }
    }
}

/// The chips and the chosen chip's content.
private struct HealthColumn: View {
    @Binding var selection: HealthChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionChips(options: HealthChip.allCases, selection: $selection, idPrefix: "health-chip",
                         id: { $0.rawValue }, title: { $0.title })
            HealthChipBody(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("health-host")
    }
}

private struct HealthChipBody: View {
    let chip: HealthChip

    var body: some View {
        UnifiedChipMount(host: "health", name: chip.rawValue, content: content)
    }

    private var content: AnyView {
        switch chip {
        case .day: return AnyView(MyDayView().containerIdentifier("health-chip-content-day"))
        case .sleep: return AnyView(HealthSleepChip())
        case .recovery: return AnyView(HealthRecoveryChip())
        case .body: return AnyView(HealthBodyChip())
        case .vitals: return AnyView(HealthVitalsChip())
        case .journal: return AnyView(HealthJournalChip())
        case .trends: return AnyView(HealthTrendsChip())
        }
    }
}

// MARK: - Chips

/// Sleep, with Alarms and Rhythm one tap away.
private struct HealthSleepChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Around sleep") {
                IndexRow("Alarms", "alarm.fill", MoreDestination.alarms, id: "health-sleep-alarms")
                IndexRow("Rhythm", "waveform.path", MoreDestination.rhythm, id: "health-sleep-rhythm")
            }
            // The Sleep screen pulls its night hero up by the scaffold's own 24 pt top inset; this restores it so the hero starts below
            // the rows instead of under them.
            SleepView()
                .padding(.top, 24)
        }
        .containerIdentifier("health-chip-content-sleep")
    }
}

/// Recovery: the three readings (NOOP, PaceForge and Garmin, never merged), the readiness panel with the coach's decision, and the
/// Charge, Effort and Rest details the rings on Today open. The details are rows, not mounted: a metric detail owns its own scroll view.
private struct HealthRecoveryChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            RecoveryThreeReadings()
            PFDualReadinessHost()
            IndexSection("Open the detail") {
                IndexRow("Charge", "bolt.heart.fill", TabRoute.metric(HeroRingMetric.charge), id: "health-recovery-charge")
                IndexRow("Effort", "flame.fill", TabRoute.metric(HeroRingMetric.effort), id: "health-recovery-effort")
                IndexRow("Rest", "moon.zzz.fill", TabRoute.metric(HeroRingMetric.rest), id: "health-recovery-rest")
            }
        }
        .containerIdentifier("health-chip-content-recovery")
    }
}

/// Vitals: Stress and Healthspan one tap away, then the Health Monitor.
private struct HealthVitalsChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Open") {
                IndexRow("Stress", "bolt.heart.fill", TabRoute.stress, id: "health-vitals-stress")
                IndexRow("Healthspan", "hourglass", TabRoute.healthspan, id: "health-vitals-healthspan")
            }
            HealthView()
        }
        .containerIdentifier("health-chip-content-vitals")
    }
}

/// The journal (and the experiments in it), with Journal impact one tap away.
private struct HealthJournalChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Journal impact") {
                IndexRow("Journal impact", "book.closed.fill", TabRoute.journalImpact, id: "health-journal-impact")
            }
            InsightsView(embedded: true)
        }
        .containerIdentifier("health-chip-content-journal")
    }
}

/// The Trends screen, under Compare and the Metric Explorer.
private struct HealthTrendsChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Look closer") {
                IndexRow("Compare", "rectangle.split.2x1.fill", TabRoute.compare, id: "health-trends-compare")
                IndexRow("Metric Explorer", "square.grid.2x2.fill", TabRoute.metricExplorer, id: "health-trends-explorer")
            }
            TrendsView()
        }
        .containerIdentifier("health-chip-content-trends")
    }
}
#endif
