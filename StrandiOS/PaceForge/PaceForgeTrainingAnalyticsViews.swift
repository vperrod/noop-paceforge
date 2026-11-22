import SwiftUI
import StrandDesign

// The screens of PaceForgeTrainingAnalytics.swift (the rules and the documents are there and unit-tested):
//  - on a run's analysis: comparable earlier runs with the ones left out and why, and each repetition against the plan;
//  - on the Athlete heart-rate zones page: a way into zone sets per sport and effective date;
//  - on a race: course and pacing notes.
// Nothing is estimated here: what the server could not check is said to be not known.

// MARK: Comparable earlier runs

struct PFComparableSessionsCard: View {
    let activityID: String

    @State private var doc: PFComparableDoc?
    @State private var failed = false
    @State private var showsExcluded = false

    var body: some View {
        PFCard("Comparable earlier runs", icon: "arrow.left.arrow.right") {
            content
        }
        .containerIdentifier("pf-comparable-sessions")
        .task(id: activityID) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let doc {
            if doc.isAvailable {
                loaded(doc)
            } else {
                PFParagraph(doc.reason.map { PFFormat.capitalized($0) + "." } ?? "No comparison is available for this activity.")
            }
        } else if failed {
            PFParagraph("The comparison could not be loaded.")
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Looking at earlier runs").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func loaded(_ doc: PFComparableDoc) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earlier runs from the last \(doc.windowDays) days that can fairly be set against this one. What was checked is listed with each; what could not be checked says not known.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if doc.comparable.isEmpty {
                PFParagraph("None of your earlier runs is a fair match yet. The list below says why each was left out.")
            }
            ForEach(doc.comparable) { run in
                VStack(alignment: .leading, spacing: 3) {
                    Text(PFFormat.shortDate(run.date) + " \u{00B7} " + run.name)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(run.summary).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if !run.matchLines.isEmpty {
                        Text(run.matchLines.joined(separator: " \u{00B7} "))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-comparable-\(run.id)")
            }
            if doc.olderThanWindow > 0 {
                Text(doc.olderThanWindow == 1 ? "1 older run is outside the last \(doc.windowDays) days and is not listed."
                     : "\(doc.olderThanWindow) older runs are outside the last \(doc.windowDays) days and are not listed.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if !doc.excluded.isEmpty {
                DisclosureGroup(isExpanded: $showsExcluded) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(doc.excluded) { run in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PFFormat.shortDate(run.date) + " \u{00B7} " + run.name)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(run.reasonText + (run.detail.map { " (\($0))" } ?? ""))
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("pf-comparable-excluded-\(run.id)")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Left out (\(doc.excluded.count))").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
                .accessibilityIdentifier("pf-comparable-excluded")
            }
        }
    }

    @MainActor private func load() async {
        doc = nil
        failed = false
        guard !activityID.isEmpty, activityID.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            failed = true
            return
        }
        do {
            let data = try await PFAPI.fetch("api/comparable-sessions?activity_id=\(activityID)")
            doc = PFComparable.parse(data)
        } catch {
            failed = true
        }
    }
}

// MARK: Repetitions against the plan

struct PFRepsCard: View {
    let sessionID: String

    @State private var doc: PFRepsDoc?
    @State private var failed = false

    var body: some View {
        PFCard("Repetitions against the plan", icon: "list.number") {
            content
        }
        .containerIdentifier("pf-session-reps")
        .task(id: sessionID) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let doc {
            if doc.isAvailable {
                loaded(doc)
            } else {
                PFParagraph(doc.reason.map { PFFormat.capitalized($0) + "." } ?? "The repetitions of this session are not available.")
            }
        } else if failed {
            PFParagraph("The repetitions could not be loaded.")
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading the laps").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func loaded(_ doc: PFRepsDoc) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(doc.reps) { rep in
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rep \(rep.n) of \(doc.plannedReps)").font(StrandFont.overline).foregroundStyle(StrandPalette.textTertiary)
                    Text("Planned: " + rep.plannedLine).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text("Recorded: " + rep.actualLine).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    if let verdict = rep.paceVerdict { verdictLine(verdict, isGood: rep.paceInBand == true) }
                    if let verdict = rep.heartRateVerdict { verdictLine(verdict, isGood: rep.hrInBand == true) }
                    if let note = rep.alignmentNote {
                        Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-rep-\(rep.n)")
            }
            if !doc.unmatchedLaps.isEmpty {
                Text("Laps not matched to a repetition: " + doc.unmatchedLaps.map { String($0) }.joined(separator: ", "))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if let note = doc.note {
                Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verdictLine(_ text: String, isGood: Bool) -> some View {
        Text(text)
            .font(StrandFont.caption.weight(.semibold))
            .foregroundStyle(isGood ? StrandPalette.accent : PFColor.warning)
    }

    @MainActor private func load() async {
        doc = nil
        failed = false
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionID
        do {
            doc = PFReps.parse(try await PFAPI.fetch("api/session-reps?session_id=\(encoded)"))
        } catch {
            failed = true
        }
    }
}

// MARK: The zone definition an analysis used

/// One line under a zone table that says which definition it was built from.
struct PFZonesUsedLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("pf-zones-used")
    }
}

// MARK: Zone sets per sport

/// The way in from the Athlete heart-rate zones page.
struct PFSportZonesEntry: View {
    var body: some View {
        NavigationLink {
            PFSportZonesView()
        } label: {
            PFCard("Zones by sport", icon: "heart") {
                HStack(alignment: .center, spacing: 8) {
                    PFParagraph("Different zones for running and cycling, each from a day you choose. An earlier analysis keeps the zones it used.")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlete-zones-by-sport")
    }
}

struct PFSportZonesView: View {
    @StateObject private var runner = PFEditJobRunner()
    @State private var doc = PFHRZonesDoc()
    @State private var loadFailed = false
    @State private var draft = PFZoneSetDraft(effectiveFrom: PFAPI.todayISO)
    @State private var note: String?

    private var problem: String? { draft.problem(today: PFAPI.todayISO) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loadFailed { PFParagraph("The zone sets could not be loaded.") }
                if let note {
                    Text(note)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-zone-sets-note")
                }
                ForEach(doc.resolved) { resolved in resolvedCard(resolved) }
                historyCard
                formCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .navigationTitle("Zones by sport")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("pf-zone-sets")
        .task { await load() }
    }

    // MARK: In force

    private func resolvedCard(_ resolved: PFResolvedZones) -> some View {
        let name = PFFormat.capitalized(resolved.sport.replacingOccurrences(of: "_", with: " "))
        return PFCard(name + " zones now", icon: "heart.fill") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(resolved.zones) { band in
                    HStack {
                        Text("Zone \(band.zone)").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Text("\(band.low) to \(band.high) bpm").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                Text(resolved.line).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("pf-zone-sets-now-\(resolved.sport)")
    }

    // MARK: History

    @ViewBuilder private var historyCard: some View {
        let sports = Array(Set(doc.sets.map { $0.sport })).sorted()
        if !sports.isEmpty {
            PFCard("Your sets", icon: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sports, id: \.self) { sport in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(PFFormat.capitalized(sport.replacingOccurrences(of: "_", with: " ")))
                                .font(StrandFont.overline)
                                .foregroundStyle(StrandPalette.textTertiary)
                            ForEach(PFHRZones.sets(of: sport, in: doc)) { set in setRow(set) }
                        }
                    }
                    Text("A set is never edited. To correct one, add a new set.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .containerIdentifier("pf-zone-sets-history")
        }
    }

    private func setRow(_ set: PFHRZoneSet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("From " + PFFormat.shortDate(set.effectiveFrom) + " \u{00B7} " + PFHRZones.sourceLabel(set.source))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
            let floors = set.floors.enumerated().map { "Z\($0.offset + 1) \($0.element)" }.joined(separator: ", ")
            Text(floors + (set.maxHr.map { ", max \($0) bpm" } ?? ""))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            if let text = set.note { Text(text).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-zone-set-\(set.id)")
    }

    // MARK: Add a set

    private var dayBinding: Binding<Date> {
        Binding(get: { PFFormat.date(draft.effectiveFrom) }, set: { draft.effectiveFrom = PFFormat.isoString($0) })
    }

    private var formCard: some View {
        PFCard("Add a zone set", icon: "plus.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("The lowest heart rate of each zone, from the day they start. Analyses from that day on use it; earlier ones keep what they used.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Sport (like running)", text: $draft.sport)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("pf-zone-set-sport")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PFHRZones.sports, id: \.self) { sport in
                            Button { draft.sport = sport } label: {
                                Text(PFFormat.capitalized(sport))
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(draft.sportKey == sport ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 40)
                                    .background(Capsule().fill(draft.sportKey == sport ? StrandPalette.accent : Color.clear))
                                    .overlay(Capsule().stroke(StrandPalette.textTertiary.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pf-zone-set-sport-\(sport)")
                        }
                    }
                }
                DatePicker("Starts on", selection: dayBinding, displayedComponents: .date)
                    .accessibilityIdentifier("pf-zone-set-date")
                Picker("Where the zones come from", selection: $draft.source) {
                    ForEach(PFHRZones.sources) { option in Text(option.label).tag(option.key) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("pf-zone-set-source")
                ForEach(0..<5, id: \.self) { index in
                    TextField("Zone \(index + 1) starts at (bpm)", text: $draft.floorTexts[index])
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("pf-zone-set-floor-\(index + 1)")
                }
                TextField("Maximum heart rate (bpm)", text: $draft.maxHrText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("pf-zone-set-max")
                TextField("Note (optional)", text: $draft.note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("pf-zone-set-note")
                if let problem { Text(problem).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).fixedSize(horizontal: false, vertical: true) }
                PFEditJobMessage(runner: runner)
                PFWeekButton529(title: runner.isBusy ? "Saving" : "Save zone set", isProminent: true, isDisabled: runner.isBusy || problem != nil,
                                identifier: "pf-zone-set-save") { Task { await save() } }
            }
        }
        .containerIdentifier("pf-zone-set-form")
    }

    @MainActor private func load() async {
        do {
            doc = PFHRZones.parse(try await PFAPI.fetch("api/hr-zones"))
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// A refusal keeps everything typed; the form is cleared only once the server has the set.
    @MainActor private func save() async {
        note = nil
        guard await runner.run(.hrZonesAdd, inputs: draft.inputs(today: PFAPI.todayISO)) != nil else { return }
        draft = PFZoneSetDraft(effectiveFrom: PFAPI.todayISO)
        note = "Saved. Analyses from that day on use this set."
        await load()
    }
}

// MARK: Race course and pacing notes

/// The row on a race that opens the course and pacing notes.
struct PFRaceCourseRow: View {
    let date: String
    let name: String?

    @State private var context: PFCourseContext?
    @State private var isOpen = false

    private var summary: String {
        guard let context else { return "Add the course, the climbing and your pacing plan" }
        var parts: [String] = []
        if let gain = context.elevationGainM { parts.append("\(gain) m of climbing") }
        if context.courseNote != nil { parts.append("course noted") }
        if context.pacingNote != nil { parts.append("pacing noted") }
        if context.url != nil { parts.append("link saved") }
        return parts.isEmpty ? "Add the course, the climbing and your pacing plan" : parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        Button { isOpen = true } label: {
            PFRow529(title: "Course and pacing notes", sub: summary, showsChevron: true).padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("race-course")
        .sheet(isPresented: $isOpen, onDismiss: { Task { await load() } }) {
            PFRaceCourseSheet(date: date, name: name, context: context)
        }
        .task(id: date) { await load() }
    }

    @MainActor private func load() async {
        context = PFCourse.context(in: await PFAPI.fetchOptional("data/events.json"), date: date, name: name)
    }
}

/// Course, climbing, link and pacing plan of one race, written by hand. Only what changed is sent (`event-update`); a part emptied is cleared.
struct PFRaceCourseSheet: View {
    let date: String
    let name: String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var draft: PFCourseDraft
    private let original: PFCourseDraft

    init(date: String, name: String?, context: PFCourseContext?) {
        self.date = date
        self.name = name
        original = PFCourseDraft(context)
        _draft = State(initialValue: PFCourseDraft(context))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        PFOver529(text: "The course")
                        TextField("e.g. four 1 km laps, carpet", text: $draft.courseNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .accessibilityIdentifier("race-course-note")
                        PFOver529(text: "Climbing in metres")
                        TextField("e.g. 120", text: $draft.elevationText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("race-course-elevation")
                        PFOver529(text: "Link to the course map")
                        TextField("https://", text: $draft.url)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("race-course-url")
                        PFOver529(text: "Pacing plan")
                        TextField("e.g. hold 4:50 for the first three runs", text: $draft.pacingNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .accessibilityIdentifier("race-pacing-note")
                    }
                    .planCard529()
                    Text("These are your own notes. Nothing is looked up or guessed for you. Leave a box empty to clear it.")
                        .font(LookFont.text(12.5))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let problem = draft.problem { Text(problem).font(LookFont.text(12.5)).foregroundStyle(PFColor.warning) }
                    PFEditMessage529(runner: runner)
                    PFPillButton529(title: "Save", isMain: true, isDisabled: runner.isBusy || draft.problem != nil) { Task { await save() } }
                        .accessibilityIdentifier("race-course-save")
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .lookScreenBackground()
            .navigationTitle("Course and pacing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
        .containerIdentifier("race-course-sheet")
    }

    @MainActor private func save() async {
        let fields = draft.changes(from: original)
        guard !fields.isEmpty else {
            dismiss()
            return
        }
        if await runner.run(.eventUpdate, inputs: PFJobInputs.raceCourseSet(date: date, name: name, fields: fields)) {
            await PFUnified.model.refresh()
            dismiss()
        }
    }
}

// MARK: Other recordings on the day

extension PFEditCandidate {
    /// The other recordings of the same day, earliest first: the ones this recording can be grouped with.
    static func others(for activity: PFActivity, in snapshot: PFSnapshot) -> [PFEditCandidate] {
        let day = String((activity.startTime ?? "").prefix(10))
        guard !day.isEmpty else { return [] }
        let sameDay = snapshot.activities.values.filter { (other: PFActivity) -> Bool in
            other.id != activity.id && String((other.startTime ?? "").prefix(10)) == day && PFActivityEditRules.recordingID(other.id) != nil
        }
        return sameDay.sorted { ($0.startTime ?? "") < ($1.startTime ?? "") }.map { (other: PFActivity) -> PFEditCandidate in
            let when = PFFormat.timeOfDay(other.startTime).map { " \u{00B7} " + $0 } ?? ""
            return PFEditCandidate(id: other.id, label: (other.name ?? other.type ?? "Recording") + when)
        }
    }
}
