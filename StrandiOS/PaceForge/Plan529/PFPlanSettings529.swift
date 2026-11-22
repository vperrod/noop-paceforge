import SwiftUI
import StrandDesign

/// How your plan is built (K1): what you decide (hours a week, days off, race priorities; run days and booked classes are read here) and the
/// rules the coach follows, in plain words, then your paces. The season plan as the coach wrote it, block by block, is the last card.
struct PFPlanSettings529: View {
    @StateObject private var store = PFDocStore529<PFPlanSettingsDoc>(path: PFDocPath529.settings)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading)
            case .empty:
                PFDocPlaceholder529(kind: .empty, emptyTitle: "Nothing here yet",
                                    emptyText: "PaceForge writes your settings and the coach's rules once your plan is built.")
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await store.refresh() } })
            case .loaded(let doc):
                if store.isStale { PFStaleNote529() }
                PFPlanSettingsContent529(doc: doc, reload: { await store.refresh() })
            }
            PFSeasonPlanCard()
            PFGuidesLinkRow530()
        }
        .planScreen529(title: "How your plan is built", identifier: "plan529-plan-settings")
        .task {
            await store.refreshIfStale()
            // The season plan card draws nothing until the coach panels store has its document.
            await PFCoachPanelsStore.shared.refreshIfStale()
        }
        .reloadsAfterPull529 { await store.refresh() }
    }
}

struct PFPlanSettingsContent529: View {
    let doc: PFPlanSettingsDoc
    let reload: () async -> Void

    @State private var editsHours = false
    @State private var editsDaysOff = false
    @State private var showsAllRules = false

    /// The rules shown before "See all".
    private static let firstRules = 7

    private var rules: [PFPlanSettingsDoc.Rule] { doc.coachFollows ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let settings = doc.youDecide, !settings.isEmpty { decideCard(settings) }
            if !rules.isEmpty { rulesCard }
            if let paces = doc.paces {
                VStack(alignment: .leading, spacing: 6) {
                    PFOver529(text: "Your paces and zones")
                    Text(paces)
                        .font(LookFont.text(13.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .planCard529()
                .accessibilityIdentifier("settings-paces")
            }
        }
        .sheet(isPresented: $editsHours) { PFHoursSheet529(hours: hours, saved: reload) }
        .sheet(isPresented: $editsDaysOff) { PFDaysOffSheet529(days: daysOff, saved: reload) }
    }

    private var hours: Double {
        for setting in doc.youDecide ?? [] where setting.editable == "hours" {
            if case .number(let value)? = setting.value { return value }
        }
        return 6
    }

    private var daysOff: [PFPlanSettingsDoc.DayOff] {
        for setting in doc.youDecide ?? [] where setting.editable == "days_off" {
            if case .days(let days)? = setting.value { return days }
        }
        return []
    }

    // MARK: You decide

    private func decideCard(_ settings: [PFPlanSettingsDoc.Setting]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "You decide")
                .padding(.bottom, 4)
            ForEach(Array(settings.enumerated()), id: \.offset) { index, setting in
                if index > 0 { PFDivider529() }
                settingRow(setting)
            }
        }
        .planCard529()
        .containerIdentifier("settings-you-decide")
    }

    @ViewBuilder private func settingRow(_ setting: PFPlanSettingsDoc.Setting) -> some View {
        let id = "settings-row-\(setting.key ?? setting.title ?? "row")"
        switch setting.editable ?? "" {
        case "hours":
            Button { editsHours = true } label: {
                PFRow529(title: setting.title ?? "Hours a week", sub: setting.sub, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        case "days_off":
            Button { editsDaysOff = true } label: {
                PFRow529(title: setting.title ?? "Days off", sub: setting.sub, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        case "priorities":
            NavigationLink {
                PFRacePriorities529()
            } label: {
                PFRow529(title: setting.title ?? "Race priorities", sub: setting.sub, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        default:
            // Run days and booked classes come from your calendar: they are read here and changed there.
            PFRow529(title: setting.title ?? "", sub: setting.sub)
                .accessibilityIdentifier(id)
        }
    }

    // MARK: The coach follows

    private var rulesCard: some View {
        let shown = showsAllRules ? rules : Array(rules.prefix(Self.firstRules))
        return VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "The coach follows")
                .padding(.bottom, 4)
            ForEach(Array(shown.enumerated()), id: \.offset) { index, rule in
                if index > 0 { PFDivider529() }
                PFRow529(title: rule.text ?? "", sub: rule.sub)
            }
            if !showsAllRules, rules.count > Self.firstRules {
                PFDivider529()
                Button { showsAllRules = true } label: {
                    PFRow529(title: "See all \(rules.count)", showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-see-all-rules")
            }
        }
        .planCard529()
        .containerIdentifier("settings-coach-follows")
    }
}

// MARK: Race priorities

/// The races to come with their priority; each opens its race page, where the priority is chosen.
struct PFRacePriorities529: View {
    @StateObject private var store = PFDocStore529<PFSeasonDoc>(path: PFDocPath529.season)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading)
            case .empty:
                PFDocPlaceholder529(kind: .empty, emptyTitle: "No races yet", emptyText: "Add a race from Season.")
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await store.refresh() } })
            case .loaded(let doc):
                VStack(alignment: .leading, spacing: 0) {
                    // A race with no date has no page to open, so it is left out.
                    ForEach(Array((doc.races ?? []).filter { $0.date?.isEmpty == false }.enumerated()), id: \.offset) { index, race in
                        if index > 0 { PFDivider529() }
                        NavigationLink(value: TabRoute.plan529(.race(date: race.date ?? ""))) {
                            PFRow529(lead: race.dayLabel, title: race.short ?? race.name ?? "Race", sub: race.sub,
                                     trailingPill: pfPriorityPill529(race, short: true), showsChevron: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("priorities-race-\(race.date ?? String(index))")
                    }
                }
                .planCard529()
            }
        }
        .planScreen529(title: "Race priorities", identifier: "plan529-race-priorities")
        .task { await store.refreshIfStale() }
    }
}

// MARK: Hours a week

/// Hours a week with a stepper (`plan-hours`).
struct PFHoursSheet529: View {
    let saved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var hours: Double

    init(hours: Double, saved: @escaping () async -> Void) {
        self.saved = saved
        _hours = State(initialValue: hours)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Stepper(value: $hours, in: 1...40, step: 0.5) {
                            Text("\(PFHours529.text(hours)) a week")
                                .font(LookFont.text(17, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                        }
                        .accessibilityIdentifier("hours-stepper")
                        Text("The coach keeps each week at or under this, and never more than 15 % above your typical week.")
                            .font(LookFont.text(12.5))
                            .foregroundStyle(NoopLook.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .planCard529()
                    PFEditMessage529(runner: runner)
                    PFPillButton529(title: "Save", isMain: true, isDisabled: runner.isBusy) { Task { await save() } }
                        .accessibilityIdentifier("hours-save")
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle("Hours a week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
        .containerIdentifier("hours-sheet")
    }

    private func save() async {
        if await runner.run(.planHours, inputs: PFPlanInputs529.hours(hours)) {
            await saved()
            dismiss()
        }
    }
}

// MARK: Days off

/// The days off that are set, each with a Remove, and a way to add one. (`dayoff-remove`, `dayoff-add`).
struct PFDaysOffSheet529: View {
    let saved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    /// The days off as the plan settings document holds them now: the parent hands the sheet its current list each time the document is
    /// read again, so a day added in the nested sheet appears and can be removed without reopening.
    let allDays: [PFPlanSettingsDoc.DayOff]
    /// Ids removed here and not yet gone from the document (the reload is on its way).
    @State private var removed: Set<String> = []
    @State private var adds = false

    /// Days added here that the document has not shown yet.
    @State private var added: [PFPlanSettingsDoc.DayOff] = []

    private var days: [PFPlanSettingsDoc.DayOff] {
        // A day added here counts as shown once the document holds it: by id, or by the same start, end and label (a day the server gave
        // no id for is held here under a local one).
        let known = Set(allDays.compactMap(\.id))
        let pending = added.filter { day in
            !(day.id.map { known.contains($0) } ?? false)
                && !allDays.contains { $0.start == day.start && ($0.end ?? $0.start) == (day.end ?? day.start) && $0.label == day.label }
        }
        return (allDays + pending).filter { day in day.id.map { !removed.contains($0) } ?? true }
    }

    init(days: [PFPlanSettingsDoc.DayOff], saved: @escaping () async -> Void) {
        self.saved = saved
        allDays = days
    }

    private func span(_ day: PFPlanSettingsDoc.DayOff) -> String {
        guard let start = day.start else { return "" }
        guard let end = day.end, end != start else { return PFFormat.dayTitle(start) }
        return PFFormat.span(start, end)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        if days.isEmpty {
                            Text("No days off are set.")
                                .font(LookFont.text(14))
                                .foregroundStyle(NoopLook.textTertiary)
                        }
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            if index > 0 { PFDivider529() }
                            HStack(spacing: 10) {
                                PFRow529(title: day.label ?? "Day off", sub: span(day))
                                if let id = day.id {
                                    Button("Remove", role: .destructive) { Task { await remove(id) } }
                                        .buttonStyle(.bordered)
                                        .disabled(runner.isBusy)
                                        .accessibilityIdentifier("day-off-remove-\(id)")
                                }
                            }
                        }
                    }
                    .planCard529()
                    PFEditMessage529(runner: runner)
                    PFPillButton529(title: "Add a day off", isMain: true) { adds = true }
                        .accessibilityIdentifier("days-off-add")
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle("Days off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .containerIdentifier("days-off-sheet")
        // Once the reloaded document holds a day added here, the local copy is dropped.
        .onChange(of: allDays) { _, now in
            added.removeAll { day in
                now.contains { ($0.id != nil && $0.id == day.id) || ($0.start == day.start && ($0.end ?? $0.start) == (day.end ?? day.start) && $0.label == day.label) }
            }
        }
        .sheet(isPresented: $adds) { PFDayOffSheet529(day: PFAPI.todayISO, saved: saved, onAdded: { added.append($0) }) }
    }

    private func remove(_ id: String) async {
        // A day off the server no longer knows ("No day off with that id") is gone, which is what was asked.
        if await runner.run(.dayoffRemove, inputs: ["id": id], isAlreadyDone: { $0.lowercased().hasPrefix("no day off") }) {
            removed.insert(id)
            await saved()
        }
    }
}
