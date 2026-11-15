import SwiftUI
import StrandDesign

/// One race (S2): days to go and the goal, how much the race matters (A, B or C, with what each does to the weeks), what the block
/// trains, the dates of every step, and the rows for pacing, editing and cancelling. After the race the same page shows the result,
/// the coach's debrief when there is one, and the way into the results sheet.
struct PFRacePage529: View {
    let date: String

    @StateObject private var store = PFDocStore529<PFSeasonDoc>(path: PFDocPath529.season)
    /// A date edit moves the race; the page follows it.
    @State private var currentDate: String

    init(date: String) {
        self.date = date
        _currentDate = State(initialValue: date)
    }

    private var upcoming: PFSeasonDoc.Race? { store.doc?.races?.first { $0.date == currentDate } }
    private var past: PFSeasonDoc.PastRace? { store.doc?.pastRaces?.first { $0.date == currentDate } }

    private var title: String {
        if let upcoming { return upcoming.short ?? upcoming.name ?? "Race" }
        if let past { return past.name ?? "Race" }
        return "Race"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading)
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await store.refresh() } })
            case .empty:
                PFRaceNotFound529(date: currentDate)
            case .loaded:
                if store.isStale { PFStaleNote529() }
                if let upcoming {
                    PFUpcomingRace529(race: upcoming, reload: { await store.refresh() }, dateChanged: { currentDate = $0 })
                } else if let past {
                    PFPastRace529(race: past)
                } else {
                    PFRaceNotFound529(date: currentDate)
                }
            }
        }
        .planScreen529(title: title, identifier: "plan529-race")
        .task { await store.refreshIfStale() }
        .reloadsAfterPull529 { await store.refresh() }
    }
}

/// A race the season does not hold (cancelled, or moved): the way to its race report is still here.
struct PFRaceNotFound529: View {
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This race is not in your season")
                .font(LookFont.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Text("It may have been cancelled or moved. Add a race again from Season.")
                .font(LookFont.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: TabRoute.reports("race:" + date)) {
                PFRow529(title: "Race report for \(PFFormat.dayTitle(date))", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("race-report-row")
        }
        .planCard529()
        .containerIdentifier("race-not-found")
    }
}

struct PFTile529: View {
    let value: String
    var sub: String? = nil
    var valueSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(LookFont.numeral(valueSize))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let sub {
                Text(sub)
                    .font(LookFont.text(11.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.row))
        .accessibilityElement(children: .combine)
    }
}

/// "How ready you are": the readiness line the old race card on Season carried, from the PaceForge snapshot (it draws nothing until the
/// snapshot holds the race).
struct PFRaceReadiness529: View {
    let date: String?

    @ObservedObject private var model = PFUnified.model

    var body: some View {
        if let race = model.snapshot?.insights.races.first(where: { $0.date == date }) {
            PFRaceCard(race: race)
                .containerIdentifier("race-readiness")
        }
    }
}

// MARK: A race to come

struct PFUpcomingRace529: View {
    let race: PFSeasonDoc.Race
    let reload: () async -> Void
    let dateChanged: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    /// The priority just saved, shown at once; the reloaded document confirms it.
    @State private var chosen: String?
    @State private var showsPacing = false
    @State private var showsEdit = false
    @State private var confirmsCancel = false

    private var selected: String? {
        if let chosen { return chosen }
        return race.prioritySet == true ? race.priority : nil
    }

    private var daysText: String {
        guard let days = race.daysOut else { return "\u{2013}" }
        if days == 0 { return "Today" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    private var options: [PFSeasonDoc.PriorityOption] {
        if let options = race.priorityOptions, !options.isEmpty { return options }
        // The server's own list carries what each choice does; without it only the names are shown.
        return [PFSeasonDoc.PriorityOption(key: "A", title: "the one you peak for", sub: nil),
                PFSeasonDoc.PriorityOption(key: "B", title: "important, not the peak", sub: nil),
                PFSeasonDoc.PriorityOption(key: "C", title: "a training race", sub: nil)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PFTile529(value: daysText, sub: [race.dayLabel, race.format].compactMap { $0 }.joined(separator: " \u{00B7} "))
                PFTile529(value: race.goal ?? "No goal", sub: race.goalSub ?? (race.goal == nil ? "Set one under Edit" : "your goal"))
            }
            .planCard529()
            .containerIdentifier("race-days-goal")
            PFRaceReadiness529(date: race.date)
            priorityCard
            if let aim = race.aim {
                VStack(alignment: .leading, spacing: 6) {
                    PFOver529(text: "What the block trains")
                    Text(aim)
                        .font(LookFont.text(14.5))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .planCard529()
                .containerIdentifier("race-block")
            }
            if let timeline = race.timeline, !timeline.isEmpty { timelineCard(timeline) }
            actionsCard
        }
        .sheet(isPresented: $showsPacing) { PFHyroxSheet() }
        .sheet(isPresented: $showsEdit) {
            PFRaceEditSheet529(race: race) { newDate in
                if let newDate, newDate != race.date { dateChanged(newDate) }
                Task { await reload() }
            }
        }
        .confirmationDialog("Cancel this race? It is removed from your list.", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Cancel race", role: .destructive) { Task { await cancel() } }
        }
    }

    // MARK: Priority

    private var priorityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "How much does this race matter?")
                .padding(.bottom, 4)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { PFDivider529() }
                let key = option.key ?? ""
                let isOn = selected == key
                Button { Task { await choose(key) } } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(key) \u{00B7} \(option.title ?? "")")
                                .font(LookFont.text(15, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                                .multilineTextAlignment(.leading)
                            if let sub = option.sub {
                                Text(sub)
                                    .font(LookFont.text(12.5))
                                    .foregroundStyle(NoopLook.textTertiary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if selected == nil, race.priority == key {
                            Text("assumed")
                                .font(LookFont.text(12))
                                .foregroundStyle(NoopLook.trendDown)
                        }
                        Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isOn ? StrandPalette.accent : NoopLook.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 9)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(runner.isBusy)
                .accessibilityValue(isOn ? "selected" : "not selected")
                .accessibilityIdentifier("race-priority-\(key)")
            }
            if selected == nil, let note = race.priorityNote {
                Text(note)
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            PFEditMessage529(runner: runner).padding(.top, 6)
        }
        .planCard529()
        .containerIdentifier("race-priority")
    }

    private func choose(_ key: String) async {
        guard !key.isEmpty, selected != key else { return }
        let inputs = PFPlanInputs529.raceSet(date: race.date ?? "", name: race.name, fields: ["priority": key])
        if await runner.run(.eventUpdate, inputs: inputs) {
            chosen = key
            await reload()
        }
    }

    // MARK: Timeline and rows

    private func timelineCard(_ timeline: [PFSeasonDoc.TimelineRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "What happens when")
                .padding(.bottom, 4)
            ForEach(Array(timeline.enumerated()), id: \.offset) { index, row in
                if index > 0 { PFDivider529() }
                PFRow529(lead: row.when, leadWidth: 64, dot: row.race == true ? PFPhase529.color("race") : nil,
                         title: row.title ?? "", sub: row.sub)
            }
        }
        .planCard529()
        .containerIdentifier("race-timeline")
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            if race.isHyrox == true {
                Button { showsPacing = true } label: {
                    PFRow529(title: "Predicted time and pacing", showsChevron: true).padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("race-pacing")
                PFDivider529()
            }
            if race.packReady == true, let date = race.date {
                NavigationLink(value: TabRoute.reports("race:" + date)) {
                    PFRow529(title: "Race pack", showsChevron: true).padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("race-pack")
                PFDivider529()
            }
            Button { showsEdit = true } label: {
                PFRow529(title: "Edit goal, date or partner", showsChevron: true).padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("race-edit")
            PFDivider529()
            Button { confirmsCancel = true } label: {
                PFRow529(title: "Cancel this race", showsChevron: true).padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(runner.isBusy)
            .accessibilityIdentifier("race-cancel")
        }
        .planCard529(padding: 0)
        .containerIdentifier("race-actions")
    }

    private func cancel() async {
        guard let date = race.date, let name = race.name else { return }
        if await runner.cancelRace(date: date, name: name) {
            await reload()
            await PFUnified.model.refresh()
            dismiss()
        }
    }
}

// MARK: Edit

/// Goal time, date and partner of one race. Only what changed is sent (`event-update`, server pending).
struct PFRaceEditSheet529: View {
    let race: PFSeasonDoc.Race
    /// Called after a save, with the new date when the date moved.
    let saved: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var goal: String
    @State private var day: Date
    @State private var partner: String

    init(race: PFSeasonDoc.Race, saved: @escaping (String?) -> Void) {
        self.race = race
        self.saved = saved
        _goal = State(initialValue: race.goal ?? "")
        _day = State(initialValue: PFFormat.date(race.date ?? PFFormat.isoString(Date())))
        _partner = State(initialValue: race.partner ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        PFOver529(text: "Goal time")
                        TextField("1:00:00", text: $goal)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("race-edit-goal")
                        PFOver529(text: "Date")
                        DatePicker("Race day", selection: $day, displayedComponents: .date)
                            .labelsHidden()
                            .accessibilityIdentifier("race-edit-date")
                        PFOver529(text: "Partner")
                        TextField("Doubles partner", text: $partner)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("race-edit-partner")
                    }
                    .planCard529()
                    PFEditMessage529(runner: runner)
                    PFPillButton529(title: "Save", isMain: true, isDisabled: runner.isBusy) { Task { await save() } }
                        .accessibilityIdentifier("race-edit-save")
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
            }
            .lookScreenBackground()
            .navigationTitle("Edit race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
        .containerIdentifier("race-edit-sheet")
    }

    private func save() async {
        let newGoal = goal.trimmingCharacters(in: .whitespaces)
        guard PFPlanInputs529.isGoalTime(newGoal) else {
            runner.fail("The goal time looks like 1:05:00 or 22:30.")
            return
        }
        var fields: [String: String] = [:]
        if newGoal != (race.goal ?? "") { fields["goal_time"] = newGoal }
        let newDate = PFFormat.isoString(day)
        if newDate != race.date { fields["date"] = newDate }
        let newPartner = partner.trimmingCharacters(in: .whitespaces)
        if newPartner != (race.partner ?? "") { fields["partner"] = newPartner }
        guard !fields.isEmpty else {
            dismiss()
            return
        }
        let inputs = PFPlanInputs529.raceSet(date: race.date ?? "", name: race.name, fields: fields)
        if await runner.run(.eventUpdate, inputs: inputs) {
            saved(fields["date"])
            dismiss()
        }
    }
}

// MARK: A race that is over

struct PFPastRace529: View {
    let race: PFSeasonDoc.PastRace

    @ObservedObject private var model = PFUnified.model
    @State private var results: PFResultsTarget529?

    /// The coach's debrief: the headline of the analysis of the recording made on the race day, when PaceForge has written it.
    private var debrief: String? {
        guard let id = race.activityId else { return nil }
        return model.snapshot?.analyses[id]?.headline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = race.result {
                HStack(spacing: 8) {
                    PFTile529(value: result.time ?? "\u{2013}", sub: race.date.map { PFFormat.dayTitle($0) })
                        .accessibilityIdentifier("race-result-time")
                    PFTile529(value: result.delta ?? "\u{2013}", sub: "against your goal", valueSize: 16)
                        .accessibilityIdentifier("race-result-delta")
                }
                .planCard529()
                .containerIdentifier("race-result")
            }
            if let debrief {
                VStack(alignment: .leading, spacing: 6) {
                    PFOver529(text: "The coach's debrief")
                    Text(debrief)
                        .font(LookFont.text(14.5))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .planCard529()
                .containerIdentifier("race-debrief")
            }
            VStack(spacing: 0) {
                if let id = race.activityId {
                    Button { results = PFResultsTarget529(activityId: id, name: race.name, date: race.date ?? "", isRace: true) } label: {
                        PFRow529(title: "Open the results", sub: "Where the time went, run by run", showsChevron: true)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("race-open-results")
                    PFDivider529()
                }
                if let date = race.date {
                    NavigationLink(value: TabRoute.reports("race:" + date)) {
                        PFRow529(title: "Race pack and report", showsChevron: true).padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("race-report-row")
                }
            }
            .planCard529(padding: 0)
        }
        .resultsSheet529($results)
    }
}
