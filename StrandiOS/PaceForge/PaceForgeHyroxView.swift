import SwiftUI
import StrandDesign

// The HYROX screen: seven sections in this order, each loading, empty and failing on its own: the next race (with the race picker),
// your plan (read-only: it is edited on the web app), results, performance, training for HYROX, advisory and season. It sits on the
// Plan tab as the HYROX chip and opens as a sheet from the Coach race plans, the Athlete tab and the race countdown. The parsing and
// the wording are in PaceForgeHyrox.swift. His own numbers only: no predicted finish, no top 3, no field or percentile comparison.

// MARK: - Store

@MainActor
final class PFHyroxStore: ObservableObject {
    static let shared = PFHyroxStore()

    enum Phase: Equatable { case loading, loaded, failed }

    @Published private(set) var plan: PFHyroxPlan?
    @Published private(set) var planPhase: Phase = .loading
    /// The server could not be asked for the plan, so the saved copy is on screen.
    @Published private(set) var planIsSavedCopy = false
    @Published private(set) var results: PFHyroxResults?
    @Published private(set) var resultsPhase: Phase = .loading
    @Published private(set) var resultsIsSavedCopy = false
    /// The race picked in the picker (its date); nil follows the next one.
    @Published private(set) var selectedEvent: String?
    /// The last pick in the picker could not be loaded and has no saved copy: the race on screen is still the one before it.
    @Published private(set) var pickFailed = false

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    func refreshIfStale() async {
        if let lastFetch, planPhase == .loaded, resultsPhase == .loaded, Date().timeIntervalSince(lastFetch) < 60 { return }
        await refresh()
    }

    /// Overlapping callers share the load already running.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            async let planLoad: Void = loadPlan()
            async let resultsLoad: Void = loadResults()
            _ = await (planLoad, resultsLoad)
            lastFetch = Date()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    /// Picks a race in the picker and loads its plan.
    func select(_ id: String) async {
        guard id != (plan?.event?.id ?? selectedEvent) else { return }
        selectedEvent = id
        pickFailed = false
        await loadPlan()
    }

    func loadPlan() async {
        guard PFAPI.isConfigured else {
            planPhase = .failed
            return
        }
        let asked = selectedEvent
        if plan == nil { planPhase = .loading }
        let doc = await PFAPI.fetchDoc(PFHyroxDoc.racePlanPath(event: asked))
        // Another race was picked while this one was loading.
        guard asked == selectedEvent else { return }
        guard let data = doc.data else {
            if doc.failed {
                if plan == nil {
                    planPhase = .failed
                } else {
                    let outcome = PFHyroxPlanFailure.outcome(asked: asked, shownEvent: plan?.event?.id)
                    selectedEvent = outcome.selectedEvent
                    if outcome.pickFailed { pickFailed = true } else { planIsSavedCopy = true }
                }
            } else if asked != nil {
                // The picked race is no longer an upcoming HYROX race on file: back to the next one.
                selectedEvent = nil
                await loadPlan()
            } else {
                plan = nil
                planPhase = .loaded
            }
            return
        }
        guard let parsed = PFHyroxParse.plan(data) else {
            if plan == nil {
                planPhase = .failed
            } else {
                let outcome = PFHyroxPlanFailure.outcome(asked: asked, shownEvent: plan?.event?.id)
                if outcome.pickFailed {
                    selectedEvent = outcome.selectedEvent
                    pickFailed = true
                }
            }
            return
        }
        if plan != parsed { plan = parsed }
        planIsSavedCopy = doc.failed
        pickFailed = false
        planPhase = .loaded
    }

    func loadResults() async {
        guard PFAPI.isConfigured else {
            resultsPhase = .failed
            return
        }
        if results == nil { resultsPhase = .loading }
        let doc = await PFAPI.fetchDoc(PFHyroxDoc.resultsPath)
        guard let data = doc.data else {
            if doc.failed {
                if results == nil { resultsPhase = .failed } else { resultsIsSavedCopy = true }
            } else {
                results = nil
                resultsPhase = .loaded
            }
            return
        }
        guard let parsed = PFHyroxParse.results(data) else {
            if results == nil { resultsPhase = .failed }
            return
        }
        if results != parsed { results = parsed }
        resultsIsSavedCopy = doc.failed
        resultsPhase = .loaded
    }
}

// MARK: - The screen

/// The seven sections. `snapshot` feeds Training and Advisory; it is nil while the PaceForge snapshot is not loaded (the sheet), and
/// those two sections then say so while the other five carry on.
struct PFHyroxScreen: View {
    let snapshot: PFSnapshot?

    @ObservedObject private var store = PFHyroxStore.shared
    @ObservedObject private var panels = PFCoachPanelsStore.shared
    @ObservedObject private var week = PFWeekPlanStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFHyroxNextRaceCard()
            PFHyroxYourPlanCard()
            PFHyroxResultsCard()
            PFHyroxPerformanceCard()
            PFHyroxTrainingCard(snapshot: snapshot)
            PFHyroxAdvisoryCard(snapshot: snapshot)
            PFHyroxSeasonCard()
        }
        .task {
            await store.refreshIfStale()
            await panels.refreshIfStale()
            await week.refreshIfStale()
        }
    }
}

/// The screen in a sheet, for the places that have no HYROX chip next to them.
struct PFHyroxSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = PFUnified.model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFRevealBar()
                    PFHyroxScreen(snapshot: model.snapshot)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                await model.refresh()
                await PFHyroxStore.shared.refresh()
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("HYROX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("hyrox-done")
                }
            }
        }
        .environmentObject(model)
        .environment(\.pfExplainers, model.snapshot?.explainerMap ?? [:])
        .presentationDetents([.large])
        .containerIdentifier("hyrox-sheet")
    }
}

/// "Open HYROX": the screen as a sheet.
struct PFOpenHyroxButton: View {
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            HStack(spacing: 6) {
                Text("Open HYROX")
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .font(StrandFont.caption.weight(.semibold))
            .foregroundStyle(StrandPalette.accent)
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hyrox-open")
        .sheet(isPresented: $isShowing) { PFHyroxSheet() }
    }
}

/// The Insights card: his own races and where the time is, with the way into the screen.
struct PFHyroxSummaryCard: View {
    let races: [PFHyroxRaceRow]
    @ObservedObject private var store = PFHyroxStore.shared

    var body: some View {
        PFCard("HYROX", icon: "flag.checkered") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your last \(races.count) races").strandOverline()
                ForEach(races.reversed()) { race in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(race.label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Text(race.date).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                        Spacer(minLength: 8)
                        if race.isPersonalBest { PFChip(text: "PB", color: PFColor.positive) }
                        Text(race.display)
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                if let line = store.results?.timeLoss?.line {
                    Text("Where the time is").strandOverline()
                    PFParagraph(line)
                }
                PFOpenHyroxButton()
            }
        }
        .accessibilityIdentifier("pf-hyrox-summary")
        .task { await store.refreshIfStale() }
    }
}

// MARK: - Shared pieces

/// What a section says while it has nothing to draw: loading, the failure with its retry, or that the server has nothing.
private struct PFHyroxPlaceholder: View {
    let phase: PFHyroxStore.Phase
    let empty: String
    let retry: () -> Void

    var body: some View {
        switch phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                PFParagraph(PFAPI.isConfigured ? "This section could not be loaded just now." : "Set up PaceForge sync in Settings to see this.")
                Button("Try again", action: retry)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .buttonStyle(.plain)
                    .frame(minHeight: 32)
                    .accessibilityIdentifier("hyrox-retry")
            }
        case .loaded:
            PFParagraph(empty)
        }
    }
}

private struct PFHyroxHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A table that scrolls sideways: a fixed first column and fixed-width figure columns.
private struct PFHyroxTable: View {
    let header: [String]
    let rows: [[String]]
    var highlighted: Set<Int> = []
    var firstWidth: CGFloat = 116

    private let cellWidth: CGFloat = 78

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                line(header, isHeader: true, isHighlighted: false)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    line(row, isHeader: false, isHighlighted: highlighted.contains(index))
                }
            }
        }
    }

    private func line(_ cells: [String], isHeader: Bool, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(cell)
                    .font(isHeader ? StrandFont.caption.weight(.semibold) : StrandFont.subhead)
                    .foregroundStyle(color(isHeader: isHeader, isHighlighted: isHighlighted, column: index))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: index == 0 ? firstWidth : cellWidth, alignment: index == 0 ? .leading : .trailing)
            }
        }
    }

    private func color(isHeader: Bool, isHighlighted: Bool, column: Int) -> Color {
        if isHeader { return StrandPalette.textTertiary }
        if isHighlighted { return PFColor.violet }
        return column == 0 ? StrandPalette.textPrimary : StrandPalette.textSecondary
    }
}

/// A line over a few values; a Canvas, as on the Athlete tiles, so a list of them stays cheap.
private struct PFHyroxSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, let low = values.min(), let high = values.max() else { return }
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let fraction: Double = high > low ? (value - low) / (high - low) : 0.5
                let point = CGPoint(x: CGFloat(index) * step, y: size.height - CGFloat(fraction) * size.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 96, height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - 1. Next race

private struct PFHyroxNextRaceCard: View {
    @ObservedObject private var store = PFHyroxStore.shared

    var body: some View {
        PFCard("Next race", icon: "flag.checkered") {
            content
        }
        .accessibilityIdentifier("hyrox-next-race")
    }

    @ViewBuilder private var content: some View {
        if let plan = store.plan {
            VStack(alignment: .leading, spacing: 14) {
                if plan.events.count > 1 { picker(plan) }
                if let event = plan.event {
                    hero(event)
                    if plan.available {
                        PFHyroxPacing(plan: plan)
                    } else {
                        PFParagraph(plan.reason ?? "No pacing can be built yet.")
                    }
                    if let pack = plan.pack {
                        PFHyroxPackView(pack: pack)
                    } else {
                        PFHyroxHint("No race pack written for this race yet.")
                    }
                } else {
                    PFInsufficient(title: "No upcoming HYROX race", text: plan.reason ?? "Add one in Events and it shows up here.",
                                   identifier: "hyrox-no-race")
                }
                if store.pickFailed {
                    PFStaleLabel(text: PFHyroxPlanFailure.pickMessage(shown: plan.event))
                } else if store.planIsSavedCopy {
                    PFStaleLabel(text: "Couldn't refresh. Showing the last saved copy.")
                }
            }
        } else {
            PFHyroxPlaceholder(phase: store.planPhase, empty: "No upcoming HYROX race on file.") {
                Task { await store.loadPlan() }
            }
        }
    }

    private func picker(_ plan: PFHyroxPlan) -> some View {
        let selected = Binding<PFHyroxEvent>(
            get: { plan.events.first { $0.id == plan.event?.id } ?? plan.events[0] },
            set: { picked in Task { await store.select(picked.id) } })
        return SectionChips(options: plan.events, selection: selected, idPrefix: "hyrox-race", id: { $0.id }, title: { $0.pickerLabel })
    }

    private func hero(_ event: PFHyroxEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(event.countdownValue)
                    .font(StrandFont.rounded(40))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityIdentifier("hyrox-days")
                if let unit = event.countdownUnit {
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.facts.joined(separator: " \u{00B7} "))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The pacing: the laps, the stations and the Roxzone, where the time is, and the Garmin 10K cross-check.
private struct PFHyroxPacing: View {
    let plan: PFHyroxPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runs").strandOverline()
            PFHyroxHint(PFHyroxFormat.runsHint(venue: plan.venue, lapProfile: plan.lapProfile))
            PFHyroxTable(header: ["Run", plan.lapProfile ? "Target lap" : "Target", "Not faster than", "Steady band"], rows: runRows)
                .accessibilityIdentifier("hyrox-runs-table")
            Text("Stations and Roxzone").strandOverline().padding(.top, 4)
            PFHyroxTable(header: ["Station", "Realistic", "Stretch", "Bad day", "Swing", "Usually vs best"], rows: stationRows,
                         highlighted: swingRows)
                .accessibilityIdentifier("hyrox-stations-table")
            PFHyroxHint(PFHyroxFormat.levelsHint(venue: plan.venue, racesOnFile: plan.racesOnFile))
            if !plan.stationsWithSwing.isEmpty {
                PFParagraph("Swing stations: " + plan.stationsWithSwing.map { "\($0.name) \($0.spreadS ?? 0) s" }.joined(separator: ", ") + ".")
            }
            if let line = PFHyroxFormat.timeToFindLine(plan) { PFParagraph(line) }
            if let garmin = plan.garmin10K { PFHyroxHint(garmin.line) }
        }
    }

    private var runRows: [[String]] {
        plan.runs.map { run in
            [run.name, PFHyroxFormat.clock(run.targetS), PFHyroxFormat.clock(run.ceilingS), run.bandText ?? "\u{2013}"]
        }
    }

    private var levels: [PFHyroxLevel] { plan.stations + (plan.roxzone.map { [$0] } ?? []) }

    private var stationRows: [[String]] {
        levels.map(stationRow)
    }

    private func stationRow(_ level: PFHyroxLevel) -> [String] {
        let isRoxzone = level.key == "Roxzone_Time"
        let spread = level.spreadS.map { "\($0) s" } ?? "\u{2013}"
        let bias = isRoxzone ? "\u{2013}" : PFHyroxFormat.signed(level.biasS)
        return [level.name, PFHyroxFormat.clock(level.realisticS), PFHyroxFormat.clock(level.stretchS), PFHyroxFormat.clock(level.badS),
                spread, bias]
    }

    private var swingRows: Set<Int> {
        var out = Set<Int>()
        for (index, level) in levels.enumerated() where level.swing { out.insert(index) }
        return out
    }
}

/// The written pack's own sections: goal and plans A and B, warm-up, cues and what to do if it goes wrong open, the rest folded.
struct PFHyroxPackView: View {
    let pack: PFHyroxPack

    private static let written: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(pack.main) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title).strandOverline()
                    PFWeekMarkdown(text: section.md)
                }
            }
            ForEach(pack.rest) { section in
                PFDisclosure(title: section.title, startsOpen: false, nested: true, id: "hyrox-pack-" + section.id) {
                    PFWeekMarkdown(text: section.md)
                }
            }
            if let updated = pack.updated {
                PFHyroxHint("Pack written " + Self.written.string(from: Date(timeIntervalSince1970: updated)) + ".")
            }
        }
        .accessibilityIdentifier("hyrox-pack")
    }
}

// MARK: - 2. Your plan

private struct PFHyroxYourPlanCard: View {
    @ObservedObject private var store = PFHyroxStore.shared

    var body: some View {
        PFCard("Your plan", icon: "pencil") {
            content
        }
        .accessibilityIdentifier("hyrox-your-plan")
    }

    @ViewBuilder private var content: some View {
        if let plan = store.plan {
            VStack(alignment: .leading, spacing: 12) {
                if let event = plan.event, plan.available {
                    if plan.yourPlan == nil {
                        PFParagraph("No plan saved for \(event.shortName). Next race shows Realistic only.")
                    } else if plan.savedPlanIsStale {
                        PFParagraph("Your saved plan is out of date: the pack changed. Edit it again on the web app.")
                            .accessibilityIdentifier("hyrox-plan-stale")
                    } else {
                        saved(plan, event: event)
                    }
                } else {
                    PFParagraph(plan.reason ?? "No upcoming HYROX race on file.")
                }
                PFHyroxHint("Edit the plan on the web app.")
            }
        } else {
            PFHyroxPlaceholder(phase: store.planPhase, empty: "No upcoming HYROX race on file.") {
                Task { await store.loadPlan() }
            }
        }
    }

    @ViewBuilder private func saved(_ plan: PFHyroxPlan, event: PFHyroxEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(PFFormat.clock(Double(plan.planTotalS)))
                    .font(StrandFont.rounded(34))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityIdentifier("hyrox-plan-total")
                Text("plan total for \(event.shortName)").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            HStack(spacing: 8) {
                PFChip(text: "Realistic \(PFFormat.clock(Double(plan.realisticTotalS)))", color: StrandPalette.textSecondary)
                if let goal = plan.goalS { PFChip(text: "Goal \(PFFormat.clock(Double(goal)))", color: StrandPalette.accent) }
            }
            let planRows = plan.planRows
            PFHyroxTable(header: ["Segment", "Realistic", "Your plan", "Change"], rows: planRows.map(tableRow),
                         highlighted: changed(planRows), firstWidth: 150)
            let held = planRows.filter { $0.isLocked }.map { $0.name }
            if !held.isEmpty { PFHyroxHint("Locked in the plan: " + held.joined(separator: ", ") + ".") }
            if let when = PFFormat.relative(plan.yourPlan?.updated) { PFHyroxHint("Saved " + when + ".") }
        }
    }

    private func tableRow(_ row: PFHyroxPlanRow) -> [String] {
        [row.name, PFHyroxFormat.clock(row.realisticS), PFHyroxFormat.clock(row.planS), PFHyroxFormat.signed(row.deltaS)]
    }

    /// The rows where the plan differs from Realistic.
    private func changed(_ rows: [PFHyroxPlanRow]) -> Set<Int> {
        var out = Set<Int>()
        for (index, row) in rows.enumerated() where row.deltaS != 0 { out.insert(index) }
        return out
    }
}

// MARK: - 3. Results

private struct PFHyroxResultsCard: View {
    @ObservedObject private var store = PFHyroxStore.shared

    var body: some View {
        PFCard("Results", icon: "list.number") {
            if let results = store.results {
                VStack(alignment: .leading, spacing: 10) {
                    if results.races.isEmpty {
                        PFInsufficient(title: "No HYROX races yet", text: "Import your races on the web app (Settings, HYROX races).",
                                       identifier: "hyrox-no-results")
                    } else {
                        PFHyroxHint("Newest first. Tap a race for its 8 runs and 8 stations.")
                        ForEach(results.races) { PFHyroxResultRow(race: $0) }
                    }
                    if store.resultsIsSavedCopy { PFStaleLabel(text: "Couldn't refresh. Showing the last saved copy.") }
                }
            } else {
                PFHyroxPlaceholder(phase: store.resultsPhase, empty: "No HYROX results on file.") {
                    Task { await store.loadResults() }
                }
            }
        }
        .accessibilityIdentifier("hyrox-results")
    }
}

private struct PFHyroxResultRow: View {
    let race: PFHyroxResultRace
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() } } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(race.title).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                            if !race.subtitle.isEmpty {
                                Text(race.subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(race.finishText).font(LookFont.numeral(20)).foregroundStyle(NoopLook.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    Text(race.summaryLine).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if race.artefact { PFChip(text: "timing artefact", color: PFColor.warning) }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(isOpen ? "Expanded" : "Collapsed"))
            .accessibilityIdentifier("hyrox-race-\(race.id)")
            if isOpen { detail }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                column("Runs", rows: race.laps.enumerated().map { ("Run \($0.offset + 1)", PFHyroxFormat.clock($0.element)) })
                column("Stations", rows: race.stations.map { ($0.name, PFHyroxFormat.clock($0.seconds)) })
            }
            ForEach(race.flags, id: \.self) { flag in PFHyroxHint(flag) }
        }
    }

    private func column(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).strandOverline()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.0).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(row.1).font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - 4. Performance

private struct PFHyroxPerformanceCard: View {
    @ObservedObject private var store = PFHyroxStore.shared

    var body: some View {
        PFCard("Performance", icon: "chart.xyaxis.line") {
            if let results = store.results {
                content(results)
            } else {
                PFHyroxPlaceholder(phase: store.resultsPhase, empty: "No HYROX results on file.") {
                    Task { await store.loadResults() }
                }
            }
        }
        .accessibilityIdentifier("hyrox-performance")
    }

    @ViewBuilder private func content(_ results: PFHyroxResults) -> some View {
        if results.stations.isEmpty {
            PFInsufficient(title: "No station times yet", text: "It fills once a race with its splits is on file.",
                           identifier: "hyrox-no-performance")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                PFHyroxHint("Your own numbers only. Last vs usual is your last race against the median of the races before it; the line runs oldest to newest.")
                ForEach(results.stations) { PFHyroxSeriesRow(series: $0) }
                if let roxzone = results.roxzone { PFHyroxSeriesRow(series: roxzone) }
                if let runs = results.runs { runLaps(runs) }
                if let line = results.timeLoss?.line {
                    Text("Where the time is").strandOverline()
                    PFParagraph(line)
                }
            }
        }
    }

    private func runLaps(_ runs: PFHyroxRunStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run laps").strandOverline()
            PFParagraph(PFHyroxFormat.lapNote(runs))
            if !runs.perRace.isEmpty {
                PFHyroxTable(header: ["Race", "Laps 2\u{2013}7 spread", "Run 8 vs laps 4\u{2013}7"], rows: runs.perRace.map(raceRow), firstWidth: 130)
            }
        }
    }

    private func raceRow(_ race: PFHyroxRunRace) -> [String] {
        let name = ((race.city ?? "") + " " + String(race.date.prefix(7))).trimmingCharacters(in: .whitespaces)
        return [name, PFFormat.trimmed(race.spreadPct) + " %", PFHyroxFormat.percent(race.run8Pct)]
    }
}

private struct PFHyroxSeriesRow: View {
    let series: PFHyroxSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(series.name).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                if let change = PFHyroxFormat.againstUsual(series) {
                    PFChip(text: change, color: (series.changeS ?? 0) > 0 ? PFColor.warning : PFColor.positive)
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                figure("Best", PFHyroxFormat.clock(series.bestS))
                figure("Median", PFHyroxFormat.clock(series.medianS))
                figure("Last", PFHyroxFormat.clock(series.lastS))
                figure("Swing", series.swingS.map { "\($0) s" } ?? "\u{2013}")
                Spacer(minLength: 4)
                PFHyroxSparkline(values: series.points, color: StrandPalette.accent)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hyrox-series-\(series.key)")
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            Text(value).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
        }
    }
}

// MARK: - 5. Training for HYROX

private struct PFHyroxTrainingCard: View {
    let snapshot: PFSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFCard("Training for HYROX", icon: "dumbbell.fill") {
                content
            }
            .accessibilityIdentifier("hyrox-training")
            // The race simulations he logged, with the button to log another.
            if let sims = snapshot?.simulations { PFSimulationsCard(sims: sims) }
        }
    }

    @ViewBuilder private var content: some View {
        if let snapshot {
            let today = snapshot.todayISO.isEmpty ? PFFormat.isoString(Date()) : snapshot.todayISO
            let found = PFHyroxTraining.sessions(weeks: snapshot.weeks, today: today)
            VStack(alignment: .leading, spacing: 14) {
                week("This week", from: found.monday, sessions: found.thisWeek, snapshot: snapshot)
                week("Next week", from: PFFormat.addDays(found.monday, 7), sessions: found.nextWeek, snapshot: snapshot)
            }
        } else {
            PFParagraph("The plan is not loaded yet. Pull down to refresh.")
        }
    }

    private func week(_ title: String, from: String, sessions: [PFWorkout], snapshot: PFSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title + " \u{00B7} " + PFFormat.span(from, PFFormat.addDays(from, 6))).strandOverline()
            if sessions.isEmpty {
                PFHyroxHint("No HYROX strength, station or compromised-run session booked.")
            } else {
                ForEach(sessions) { workout in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PFFormat.dayTitle(workout.date) + " \u{00B7} " + PFHyroxTraining.kindLabel(workout))
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                        PFWorkoutRow(workout: workout, snapshot: snapshot)
                    }
                }
            }
        }
    }
}

// MARK: - 6. Advisory

private struct PFHyroxAdvisoryCard: View {
    let snapshot: PFSnapshot?

    @ObservedObject private var week = PFWeekPlanStore.shared
    @ObservedObject private var store = PFHyroxStore.shared
    @State private var hasAsked = false

    var body: some View {
        let extra = (store.plan?.events ?? []).map(\.shortName)
        let proposals = PFHyroxAdvice.proposals(week.proposals, extra: extra)
        let raceWeek = PFHyroxAdvice.raceWeek(snapshot?.raceWeek, extra: extra)
        let brief = PFHyroxAdvice.briefLines(snapshot?.today.brief, extra: extra)
        PFCard("Advisory", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                if proposals.isEmpty && raceWeek == nil && brief.isEmpty {
                    PFHyroxHint("Nothing from the coach about the races right now. Proposals about them appear here with Accept and Reject.")
                }
                if !proposals.isEmpty {
                    Text("Proposals waiting").strandOverline()
                    ForEach(proposals) { proposal in
                        PFProposalView(proposal: proposal, onAsk: { prompt in
                            PFChatPrefill.shared.text = prompt
                            hasAsked = true
                        })
                    }
                    if hasAsked { PFHyroxHint("Your question is waiting in the chat box on the Coach screen.") }
                }
                if let raceWeek {
                    Text(raceWeekTitle(raceWeek)).strandOverline()
                    ForEach(raceWeek.notes, id: \.self) { note in PFParagraph(note) }
                }
                if !brief.isEmpty {
                    Text("From the coach's read of " + briefDay).strandOverline()
                    ForEach(brief, id: \.self) { line in PFParagraph(line) }
                }
            }
        }
        .accessibilityIdentifier("hyrox-advisory")
    }

    private var briefDay: String {
        guard let date = snapshot?.today.brief?.date else { return "today" }
        return PFFormat.dayTitle(date)
    }

    private func raceWeekTitle(_ raceWeek: PFRaceWeek) -> String {
        let days = raceWeek.daysTo ?? 0
        return "Race week \u{00B7} " + raceWeek.event.name + " \u{00B7} " + String(days) + (days == 1 ? " day" : " days") + " to go"
    }
}

// MARK: - 7. Season

private struct PFHyroxSeasonCard: View {
    @ObservedObject private var panels = PFCoachPanelsStore.shared

    var body: some View {
        PFCard("Season", icon: "calendar") {
            if panels.season == nil {
                PFParagraph("The season plan is not loaded yet.")
            } else {
                let rows = PFHyroxSeason.rows(panels.season, today: PFAPI.todayISO)
                if rows.isEmpty {
                    PFInsufficient(title: "No HYROX race in the season", text: "Add one in Events and the season is worked back from it.",
                                   identifier: "hyrox-no-season")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows) { row(row: $0) }
                    }
                }
            }
        }
        .accessibilityIdentifier("hyrox-season")
    }

    private func row(row: PFHyroxSeasonRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tone(row.priority))
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(PFFormat.dayTitle(row.date) + " \u{00B7} " + row.priorityText).font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(row.awayText + (row.assumed ? " \u{00B7} " + PFSeasonRace.assumedNote : ""))
                    .font(StrandFont.caption)
                    .foregroundStyle(row.assumed ? PFColor.warning : StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.taperText).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.blocks.isEmpty {
                    Text(row.blocks.map { $0.title + " " + $0.span }.joined(separator: " \u{00B7} "))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tone(_ priority: String?) -> Color {
        switch priority?.uppercased() {
        case "A": return PFColor.critical
        case "B": return PFColor.warning
        default: return StrandPalette.textTertiary
        }
    }
}
