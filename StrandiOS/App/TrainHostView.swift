#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Train: the third tab
//
// Chips at the top and ONE chip mounted below them: HYROX (the race plan, results and advisory, with the race reports), Running
// (predictions and heart-rate zones), Strength (the Lift Log), Bike (the recent rides), Workouts (every session) and Athlete (your
// numbers and profile). Each chip is a screen that exists elsewhere, drawn in this screen's scroll view; nothing new is fetched.

enum TrainChip: String, CaseIterable, Identifiable {
    case hyrox, running, strength, bike, workouts, athlete

    /// The chip on show. Kept between launches.
    static let storageKey = "noop.train.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hyrox: return "HYROX"
        case .running: return "Running"
        case .strength: return "Strength"
        case .bike: return "Bike"
        case .workouts: return "Workouts"
        case .athlete: return "Athlete"
        }
    }
}

/// The Train tab's root.
struct TrainHostView: View {
    @AppStorage(TrainChip.storageKey) private var chipRaw = TrainChip.hyrox.rawValue

    private var chip: TrainChip { TrainChip(rawValue: chipRaw) ?? .hyrox }

    private var selection: Binding<TrainChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip train.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Train", subtitle: "HYROX, running, strength, bike, your workouts and your athlete profile.",
                       onRefresh: {
            await PFUnified.model.refresh()
            if chip == .hyrox { await PFHyroxStore.shared.refresh() }
        }, lazy: true, topBackground: liquidScaffoldSky()) {
            TrainColumn(selection: selection)
        }
    }
}

/// The chips and the chosen chip's content.
private struct TrainColumn: View {
    @Binding var selection: TrainChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionChips(options: TrainChip.allCases, selection: $selection, idPrefix: "train-chip",
                         id: { $0.rawValue }, title: { $0.title })
            TrainChipBody(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("train-host")
    }
}

private struct TrainChipBody: View {
    let chip: TrainChip

    var body: some View {
        UnifiedChipMount(host: "train", name: chip.rawValue, content: content)
    }

    private var content: AnyView {
        switch chip {
        case .hyrox: return AnyView(TrainHyroxChip())
        case .running: return AnyView(TrainRunningChip())
        case .strength: return AnyView(LiftLogView().containerIdentifier("train-chip-content-strength"))
        case .bike: return AnyView(TrainBikeChip())
        case .workouts: return AnyView(WorkoutsView().containerIdentifier("train-chip-content-workouts"))
        case .athlete: return AnyView(AthleteHostView().containerIdentifier("train-chip-content-athlete"))
        }
    }
}

// MARK: - Chips

/// The HYROX screen (seven cards) under a row to the race reports.
private struct TrainHyroxChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(TrainHyroxContent(snapshot: snapshot)) })
    }
}

private struct TrainHyroxContent: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IndexSection("Race reports") {
                IndexRow("Race reports", "flag.checkered", TabRoute.reports("race"), id: "train-hyrox-race-reports")
            }
            PFHyroxScreen(snapshot: snapshot)
        }
        .containerIdentifier("train-chip-content-hyrox")
    }
}

/// The recent rides (newest first), each opening the ride screen.
private struct TrainBikeChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(TrainBikeContent(snapshot: snapshot)) })
    }
}

private struct TrainBikeContent: View {
    let snapshot: PFSnapshot

    /// The ride list is long once a season has run; the latest ten are shown.
    private static let shown = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if snapshot.rides.isEmpty {
                PFCard("No rides yet", icon: "bicycle") {
                    PFParagraph("Rides PaceForge has analysed show here, newest first. Planned rides are on the Plan tab.")
                }
            } else {
                ForEach(Array(snapshot.rides.prefix(Self.shown))) { ride in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(PFFormat.dayTitle(ride.date)).strandOverline()
                        PFRideRow(ride: ride, snapshot: snapshot)
                    }
                }
            }
        }
        .containerIdentifier("train-chip-content-bike")
    }
}
#endif
