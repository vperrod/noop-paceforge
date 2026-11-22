import SwiftUI
import StrandDesign

// Under the Lift Log (Train > Strength): the import of a strength CSV and PaceForge's strength history. The Lift Log above already shows
// this iPhone's own sets, bests and records, so the history here lists only what it lacks: sets that came from PaceForge's own log or from
// an import, each labelled with its source. Strength summaries (Strava, Garmin) are listed apart and never counted toward a best.

struct PFStrengthSection: View {
    @State private var history: PFStrengthHistory?
    @State private var state = LoadState.loading
    @State private var importing = false
    @State private var opened: PFStrengthHistory.Exercise?
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    private enum LoadState { case loading, loaded, failed }

    private var pounds: Bool { UnitSystem(rawValue: unitSystemRaw) == .imperial }

    var body: some View {
        if PFAPI.isConfigured {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("From PaceForge", overline: "Imports and history")
                importCard
                historyCards
            }
            .containerIdentifier("strength-server-section")
            .task { await load() }
            .sheet(isPresented: $importing) {
                PFStrengthImportSheet { await load() }
            }
            .sheet(item: $opened) { exercise in
                PFStrengthExerciseSheet(exercise: exercise, pounds: pounds)
            }
        }
    }

    private var importCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import a strength CSV")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text("Hevy sets, or a Strava or Garmin strength summary file. You see what would be saved first, and nothing is saved until you confirm.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { importing = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .buttonStyle(NoopButtonStyle(.secondary))
                    .accessibilityIdentifier("strength-import-open")
            }
        }
    }

    @ViewBuilder private var historyCards: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failed:
            NoopCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PaceForge's strength history could not be read.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    Button("Try again") { Task { await load() } }.font(StrandFont.subhead)
                }
            }
        case .loaded:
            if let history {
                let others = history.beyondThisPhone
                if others.isEmpty && history.summaries.isEmpty {
                    NoopCard {
                        Text("Nothing from PaceForge's log or an import yet. Sets from this iPhone's Lift Log are in the log above.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(others) { exercise in exerciseRow(exercise) }
                if !history.summaries.isEmpty { summariesCard(history) }
            }
        }
    }

    private func exerciseRow(_ exercise: PFStrengthHistory.Exercise) -> some View {
        Button { opened = exercise } label: {
            NoopCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 6)
                        if exercise.prCount > 0 {
                            Text("\(exercise.prCount) \(exercise.prCount == 1 ? "PR" : "PRs")")
                                .font(StrandFont.caption).foregroundStyle(PFColor.positive)
                        }
                    }
                    if let best = exercise.bestWeight {
                        Text(heaviestLine(best))
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let best = exercise.bestE1RM, let e1rm = best.e1rmKg {
                        Text(e1rmLine(best, e1rm))
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text("From " + PFStrengthHistory.sourcesLine(exercise.history))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strength-server-exercise-\(exercise.key.replacingOccurrences(of: " ", with: "-"))")
    }

    private func heaviestLine(_ best: PFStrengthHistory.Best) -> String {
        var parts = [PFStrengthHistory.setText(weightKg: best.weightKg, reps: best.reps, pounds: pounds)]
        if let date = best.date { parts.append(PFFormat.shortDate(date)) }
        parts.append(PFStrengthHistory.sourceLabel(best.source))
        return "Heaviest set: " + parts.joined(separator: " \u{00B7} ")
    }

    private func e1rmLine(_ best: PFStrengthHistory.Best, _ e1rm: Double) -> String {
        "Best estimated 1RM: \(PFStrengthHistory.weightText(kg: e1rm, pounds: pounds)) \u{00B7} \(PFStrengthHistory.sourceLabel(best.source))"
    }

    private func summariesCard(_ history: PFStrengthHistory) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session summaries").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                ForEach(history.summaries.prefix(10)) { summary in
                    HStack(alignment: .firstTextBaseline) {
                        Text(PFStrengthHistory.heading(date: summary.date, title: summary.title))
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 6)
                        Text(summary.durationSeconds.map { PFStrengthHistory.durationText(seconds: $0) } ?? "")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Text(history.summariesNote ?? "Summaries are sessions without sets. They never count toward a best.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("strength-server-summaries")
    }

    @MainActor private func load() async {
        do {
            let data = try await PFAPI.fetch("api/strength-history")
            history = PFStrengthHistory.parse(PFJ(data: data))
            state = history == nil ? .failed : .loaded
        } catch {
            if history == nil { state = .failed }
        }
    }
}

/// One exercise's recorded sets from the sources the Lift Log does not hold, newest first, a PR marked where it beat every earlier set.
struct PFStrengthExerciseSheet: View {
    let exercise: PFStrengthHistory.Exercise
    let pounds: Bool
    @Environment(\.dismiss) private var dismiss

    private func line(_ point: PFStrengthHistory.Point) -> String {
        var parts = [PFStrengthHistory.setText(weightKg: point.weightKg, reps: point.reps, pounds: pounds)]
        if let e1rm = point.e1rmKg { parts.append("est. 1RM " + PFStrengthHistory.weightText(kg: e1rm, pounds: pounds)) }
        if let rpe = point.rpe { parts.append("RPE " + PFFormat.trimmed(rpe)) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    ForEach(exercise.history) { point in
                        NoopCard {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(PFFormat.dayTitle(point.date)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                                    Spacer(minLength: 6)
                                    if point.isPR { Text("PR").font(StrandFont.caption.weight(.semibold)).foregroundStyle(PFColor.positive) }
                                }
                                Text(line(point))
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                Text(PFStrengthHistory.sourceLabel(point.source))
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                    }
                    Text("Estimated with the Epley formula, for sets of up to 12 reps. Sets from this iPhone's own Lift Log are not repeated here.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(NoopMetrics.gap)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
        }
    }
}
