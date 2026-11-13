import SwiftUI
import StrandDesign

// The Race kind of the Reports index: the races that have a pack or a debrief, newest first, and one race's page: the pack above, the
// debrief (the analysis of the activity recorded on the race day) below.

struct PFRaceReportsScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PFRaceReportsList()
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Race")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("pf-race-reports")
    }
}

/// The rows, from the snapshot and the HYROX race plan's races.
struct PFRaceReportsList: View {
    @ObservedObject private var model = PFUnified.model
    @ObservedObject private var store = PFHyroxStore.shared

    var body: some View {
        let rows = PFRaceReportRows.current(snapshot: model.snapshot, hyroxPlan: store.plan)
        VStack(alignment: .leading, spacing: 12) {
            if rows.isEmpty {
                PFCard("No race reports yet", icon: "flag.checkered") {
                    PFParagraph("A race shows here once PaceForge has written its race pack, or once the activity you recorded on the day has an analysis.")
                }
                .containerIdentifier("pf-race-reports-empty")
            } else {
                ForEach(rows) { row in
                    NavigationLink(value: TabRoute.reports("race:" + row.date)) { card(row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pf-race-report-\(row.date)")
                }
            }
        }
        .task {
            await model.refreshIfStale()
            await store.refreshIfStale()
        }
    }

    private func card(_ row: PFRaceReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(LookFont.text(17, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(PFFormat.shortDate(row.date))
                    .font(LookFont.text(12))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            Text(PFRaceReports.summary(row) + (row.goalTime.map { " \u{00B7} goal \($0)" } ?? ""))
                .font(LookFont.text(14))
                .foregroundStyle(NoopLook.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .contentShape(Rectangle())
    }
}

enum PFRaceReportRows {
    /// The rows for the snapshot; the days of the HYROX plan's races count as having a pack while the plan holds one.
    static func current(snapshot: PFSnapshot?, hyroxPlan: PFHyroxPlan?) -> [PFRaceReport] {
        guard let snapshot else { return [] }
        let packDates: Set<String> = hyroxPlan.map { plan in Set(plan.events.map { $0.date }) } ?? []
        return PFRaceReports.rows(races: snapshot.races, activities: snapshot.activities, analyses: snapshot.analyses, packDates: packDates)
    }
}

/// One race: the pack above, the debrief below.
struct PFRaceReportPage: View {
    let date: String
    @ObservedObject private var model = PFUnified.model
    @ObservedObject private var store = PFHyroxStore.shared
    @State private var resultsWorkout: PFWorkout?

    var body: some View {
        let row = PFRaceReportRows.current(snapshot: model.snapshot, hyroxPlan: store.plan).first { $0.date == date }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let row {
                    Text(row.name)
                        .font(LookFont.text(20, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Text(PFFormat.dayTitle(row.date) + (row.goalTime.map { " \u{00B7} goal \($0)" } ?? ""))
                        .font(LookFont.text(13))
                        .foregroundStyle(NoopLook.textTertiary)
                    packSection(row)
                    debriefSection(row)
                } else {
                    PFCard("Race not found", icon: "flag.checkered") {
                        PFParagraph("This race has no pack or debrief on this phone.")
                    }
                }
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Race report")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("pf-race-report-page")
        .task { await loadPack() }
        .sheet(item: $resultsWorkout) { workout in
            if let snapshot = model.snapshot { PFResultsSheet(workout: workout, snapshot: snapshot) }
        }
    }

    /// The race's pack is part of the HYROX race plan: pick the race there, which loads its plan.
    private func loadPack() async {
        await store.refreshIfStale()
        if let event = store.plan?.events.first(where: { $0.date == date }) { await store.select(event.id) }
    }

    @ViewBuilder private func packSection(_ row: PFRaceReport) -> some View {
        if let plan = store.plan, plan.event?.date == date, let pack = plan.pack {
            PFCard("Race pack", icon: "doc.text") { PFHyroxPackView(pack: pack) }
                .accessibilityIdentifier("pf-race-pack")
        } else if row.hasPack {
            PFCard("Race pack", icon: "doc.text") { PFParagraph("Loading the race pack.") }
        }
    }

    @ViewBuilder private func debriefSection(_ row: PFRaceReport) -> some View {
        if let id = row.analysisActivityID, let snapshot = model.snapshot, let analysis = snapshot.analyses[id] {
            let workout = snapshot.weeks.flatMap { $0.days.flatMap { $0.workouts } }.first { $0.activityId == id }
            PFCard("Debrief", icon: "flag.checkered") {
                VStack(alignment: .leading, spacing: 8) {
                    if let headline = analysis.headline { PFParagraph(headline) }
                    if let note = workout?.completionAnalysis { PFParagraph(note) }
                    if let workout, workout.hasResults {
                        Button { resultsWorkout = workout } label: {
                            Text("Open the results")
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(StrandPalette.accent)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pf-race-debrief-results")
                    }
                }
            }
            .accessibilityIdentifier("pf-race-debrief")
        }
    }
}
