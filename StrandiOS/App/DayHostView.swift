#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Day: the one tab
//
// The beta Day tab (Settings > Tools > New Day tab) replaces the Sleep tab. A row of chips at the top and ONE chip mounted below it
// (like Insights and Data): My Day, Sleep, Recovery, Workouts, Activity, Health. Each chip is the content of a screen that already exists,
// unchanged, drawn in this screen's scroll view. Sleep and Recovery start with a card that sets NOOP's numbers beside PaceForge's
// and Garmin's (DayReadings.swift); the numbers are never merged.
//
// Built small on purpose (builds 465 to 478): every chip is its own small view, only the selected chip is mounted, nothing here
// reads a live strap value, and there is no GeometryReader, ViewThatFits or preference key.

enum DayChip: String, CaseIterable, Identifiable {
    case myDay, sleep, recovery, workouts, activity, health

    /// The chip on show, shared with the shell so a link to Sleep can land on the Sleep chip. Reset to Sleep at every launch.
    static let storageKey = "noop.day.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myDay: return "My Day"
        case .sleep: return "Sleep"
        case .recovery: return "Recovery"
        case .workouts: return "Workouts"
        case .activity: return "Activity"
        case .health: return "Health"
        }
    }
}

/// The Day tab's root.
struct DayHostView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(DayChip.storageKey) private var chipRaw = DayChip.sleep.rawValue

    private var chip: DayChip { DayChip(rawValue: chipRaw) ?? .sleep }

    private var selection: Binding<DayChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("day.chip \(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Day", subtitle: "Your day, your sleep and your recovery in one place.",
                       onRefresh: { await repo.refresh() }, lazy: true, topBackground: liquidScaffoldSky()) {
            DayColumn(selection: selection)
        }
    }
}

/// The chips and the chosen chip's content.
private struct DayColumn: View {
    @Binding var selection: DayChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionChips(options: DayChip.allCases, selection: $selection, idPrefix: "day-chip",
                         id: { $0.rawValue }, title: { $0.title })
            DayChipBody(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("day-host")
    }
}

/// One chip's content, with its mount time in the breadcrumbs: the time from the moment the chip was chosen (this view is built
/// then) to its first appearance, and to the first pass after it, so a report shows which chip is heavy.
private struct DayChipBody: View {
    let chip: DayChip
    @State private var born = DispatchTime.now().uptimeNanoseconds

    var body: some View {
        content
            .onAppear {
                let name = chip.rawValue
                let started = born
                NoopDiag.screen("day.\(name)")
                let first = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
                NoopDiag.crumb("day.chip.mount \(name)", ["ms": first.rounded()])
                NoopPerfStats.shared.section("day.chip.mount.\(name)", ms: first, onMain: true)
                DispatchQueue.main.async {
                    let settled = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
                    NoopDiag.crumb("day.chip.settled \(name)", ["ms": settled.rounded()])
                }
            }
    }

    private var content: AnyView {
        switch chip {
        case .myDay: return AnyView(DayMyDayChip())
        case .sleep: return AnyView(DaySleepChip())
        case .recovery: return AnyView(DayRecoveryChip())
        case .workouts: return AnyView(WorkoutsView().containerIdentifier("day-chip-content-workouts"))
        case .activity: return AnyView(DayActivityChip())
        case .health: return AnyView(DayHealthChip())
        }
    }
}

// MARK: - Chips

/// My Day, as the Today tab's entry opens it. It brings its own day stepper (previous and next day), so Day adds none.
private struct DayMyDayChip: View {
    var body: some View {
        MyDayView()
            .containerIdentifier("day-chip-content-myDay")
    }
}

/// Sleep, as the Sleep tab drew it, under the three-readings card.
private struct DaySleepChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            SleepThreeReadings()
            // The Sleep screen pulls its night hero up by the scaffold's own 24 pt top inset; this restores it so the hero starts
            // below the card instead of under it.
            SleepView()
                .padding(.top, 24)
        }
        .containerIdentifier("day-chip-content-sleep")
    }
}

/// Recovery: the three-readings card, then Charge, Effort and Rest, each opening the detail the rings on Today open.
private struct DayRecoveryChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            RecoveryThreeReadings()
            DayRecoveryChooser()
        }
        .containerIdentifier("day-chip-content-recovery")
    }
}

private struct DayRecoveryChooser: View {
    var body: some View {
        IndexSection("Open the detail") {
            IndexRow("Charge", "bolt.heart.fill", TabRoute.metric(HeroRingMetric.charge), id: "day-recovery-charge")
            IndexRow("Effort", "flame.fill", TabRoute.metric(HeroRingMetric.effort), id: "day-recovery-effort")
            IndexRow("Rest", "moon.zzz.fill", TabRoute.metric(HeroRingMetric.rest), id: "day-recovery-rest")
        }
    }
}

/// Strength and activity tools, with the Lift Log one tap away. The workout history has its own chip.
private struct DayActivityChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Lifts") {
                IndexRow("Lift Log", "dumbbell.fill", TabRoute.liftLog, id: "day-activity-lifts")
            }
        }
        .containerIdentifier("day-chip-content-activity")
    }
}

/// Health: the Health Monitor, as it is, with Stress one tap away.
private struct DayHealthChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Stress") {
                IndexRow("Stress", "bolt.heart.fill", TabRoute.stress, id: "day-health-stress")
            }
            HealthView()
        }
        .containerIdentifier("day-chip-content-health")
    }
}
#endif
