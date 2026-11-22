import SwiftUI
import StrandDesign

// "Edit this recording" on a recorded activity's detail: relabel (a walk, not a run), trim, split, group and undo. The Garmin recording is never
// changed. A change is first PROPOSED: PaceForge answers with a before/after preview, and only Confirm applies it. Every applied edit is listed
// with an Undo. The rules, inputs and documents are in PaceForgeActivityEdits.swift (unit-tested); this file is the screens.

/// Runs one write at a time for a sheet and keeps the sentence to show when it did not go through. The result of a write that did is handed back.
@MainActor
final class PFEditJobRunner: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    private let tracker = PFJobTracker()

    func clear() { message = nil }

    func fail(_ text: String) { message = text }

    /// The job's result when the server took it; nil, with the server's own sentence in `message`, when it did not.
    func run(_ job: PFJobName, inputs: [String: Any]?) async -> PFJ? {
        guard let inputs else {
            message = "That could not be sent. Check the values."
            return nil
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        switch await tracker.run(job, inputs: inputs) {
        case .success(let result):
            return result
        case .failure(let failure):
            message = failure.message
            return nil
        }
    }
}

/// A line under a form or a list when a write did not go through.
struct PFEditJobMessage: View {
    @ObservedObject var runner: PFEditJobRunner

    var body: some View {
        if let message = runner.message {
            Text(message)
                .font(LookFont.text(12.5))
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pf-edit-message")
        }
    }
}

/// Another recording the athlete can group this one with.
struct PFEditCandidate: Identifiable, Equatable {
    let id: String
    let label: String
}

// MARK: The card on the activity detail

struct PFActivityEditEntry: View {
    let activityID: String
    let name: String
    let type: String?
    /// The recording's length, only to tell the athlete what the trim and split times run up to.
    let durationS: Double?
    let others: [PFEditCandidate]

    @State private var isOpen = false
    @State private var waiting = 0

    var body: some View {
        PFCard("Edit this recording", icon: "scissors") {
            VStack(alignment: .leading, spacing: 10) {
                PFParagraph("Wrong sport, a stop you forgot to press, two watches for one session? Fix it here. The Garmin recording is never changed: an edit is an overlay you can undo.")
                if waiting > 0 {
                    Text(waiting == 1 ? "1 change is waiting for your OK." : "\(waiting) changes are waiting for your OK.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-activity-edit-waiting")
                }
                PFWeekButton529(title: "Edit this recording", isProminent: true, identifier: "pf-activity-edit-open") { isOpen = true }
            }
        }
        .containerIdentifier("pf-activity-edit-entry")
        .sheet(isPresented: $isOpen, onDismiss: { Task { await countWaiting() } }) {
            PFActivityEditSheet(activityID: activityID, name: name, type: type, durationS: durationS, others: others)
        }
        .task(id: activityID) { await countWaiting() }
    }

    @MainActor private func countWaiting() async {
        let doc = PFActivityEdits.parse(await PFAPI.fetchOptional("api/activity-edits"))
        waiting = doc.proposals(for: activityID).filter { $0.isPending }.count
    }
}

// MARK: The sheet

struct PFActivityEditSheet: View {
    let activityID: String
    let name: String
    let type: String?
    let durationS: Double?
    let others: [PFEditCandidate]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFEditJobRunner()
    @State private var draft: PFActivityEditDraft
    @State private var doc = PFEditsDoc()
    @State private var loadFailed = false
    @State private var note: String?

    init(activityID: String, name: String, type: String?, durationS: Double?, others: [PFEditCandidate]) {
        self.activityID = activityID
        self.name = name
        self.type = type
        self.durationS = durationS
        self.others = others
        _draft = State(initialValue: PFActivityEditDraft(activityID: activityID, currentType: type, currentName: name, durationS: nil))
    }

    private var waiting: [PFEditProposal] { doc.proposals(for: activityID).filter { $0.isPending } }
    private var history: [PFEditRecord] { doc.history(for: activityID) }
    private var isGroup: Bool { doc.isGroup(activityID) }

    /// The edits offered: ungrouping only for a recording that is a group.
    private var ops: [PFActivityEditOp] { PFActivityEditOp.allCases.filter { $0 != .ungroup || isGroup } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(name). Nothing changes until you confirm a preview, and the Garmin recording itself is never touched.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pf-activity-edit-note")
                    }
                    ForEach(waiting) { proposal in proposalCard(proposal) }
                    formCard
                    historyCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Edit recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-activity-edit-done")
                }
            }
        }
        .containerIdentifier("pf-activity-edit-sheet")
        .task { await load() }
    }

    // MARK: A change waiting for confirmation

    private func proposalCard(_ proposal: PFEditProposal) -> some View {
        PFCard(proposal.isFromCoach ? "Coach suggests" : "Preview", icon: "eye") {
            VStack(alignment: .leading, spacing: 12) {
                Text(proposal.spec.summary)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let why = proposal.rationale { PFParagraph(why) }
                previewColumn(title: "Before", rows: proposal.preview.before, totals: proposal.preview.beforeTotals)
                previewColumn(title: "After", rows: proposal.preview.after, totals: proposal.preview.afterTotals)
                if proposal.preview.after.contains(where: { !$0.unknown.isEmpty }) {
                    Text("A figure the recording cannot give for the new part is shown as unknown, not guessed.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PFEditJobMessage(runner: runner)
                HStack(spacing: 8) {
                    PFWeekButton529(title: runner.isBusy ? "Working" : "Confirm", isProminent: true, isDisabled: runner.isBusy,
                                    identifier: "pf-activity-edit-confirm-\(proposal.id)") { Task { await confirm(proposal) } }
                    PFWeekButton529(title: "Not now", isDisabled: runner.isBusy, identifier: "pf-activity-edit-reject-\(proposal.id)") {
                        Task { await reject(proposal) }
                    }
                }
            }
        }
        .containerIdentifier("pf-activity-edit-proposal")
    }

    private func previewColumn(title: String, rows: [PFEditRow], totals: PFEditTotals?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(StrandFont.overline).foregroundStyle(StrandPalette.textTertiary)
            if rows.isEmpty {
                Text("Nothing").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(row.line).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            if let totals {
                Text("Total: " + totals.line).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    // MARK: The form

    private var formCard: some View {
        PFCard("Make an edit", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Edit", selection: $draft.op) {
                    ForEach(ops, id: \.self) { op in Text(op.title).tag(op) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("pf-activity-edit-op")
                fields
                TextField("Why (optional)", text: $draft.rationale, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("pf-activity-edit-why")
                if let problem = draft.problem {
                    Text(problem).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if waiting.isEmpty { PFEditJobMessage(runner: runner) }
                PFWeekButton529(title: runner.isBusy ? "Working" : "Preview the change", isProminent: true,
                                isDisabled: runner.isBusy || draft.problem != nil, identifier: "pf-activity-edit-propose") {
                    Task { await propose() }
                }
            }
        }
        .containerIdentifier("pf-activity-edit-form")
    }

    @ViewBuilder private var fields: some View {
        switch draft.op {
        case .relabel:
            Picker("Sport", selection: $draft.typeKey) {
                Text("Keep " + (PFActivityEditRules.label(forType: type) ?? "as it is")).tag(String?.none)
                ForEach(PFActivityEditRules.relabelTypes) { option in
                    Text(option.label).tag(Optional(option.key))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("pf-activity-edit-type")
            TextField("New name (optional)", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("pf-activity-edit-name")
        case .trim:
            if let durationS {
                Text("The recording is about \(PFFormat.clock(durationS)) long. Times are minutes and seconds from its start, like 2:30.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("New start (optional, like 2:30)", text: $draft.startText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("pf-activity-edit-start")
            TextField("New end (optional, like 38:00)", text: $draft.endText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("pf-activity-edit-end")
        case .split:
            TextField("Split at (like 20:00)", text: $draft.splitText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("pf-activity-edit-split")
            Text("The recording becomes two, each at least 10 seconds long.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        case .group:
            groupPicker
        case .ungroup:
            Text("This recording is a group. Ungrouping gives the separate recordings back.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private var groupPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if others.isEmpty {
                Text("There is no other recording on this day to group it with.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            } else {
                Text("Pick the recordings that belong to the same session. Two watches that recorded the same session at once cannot be grouped.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(others) { other in
                let isOn = draft.groupWith.contains(other.id)
                Button {
                    if isOn { draft.groupWith.remove(other.id) } else { draft.groupWith.insert(other.id) }
                } label: {
                    HStack {
                        Text(other.label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? StrandPalette.accent : StrandPalette.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isOn ? "selected" : "not selected")
                .accessibilityIdentifier("pf-activity-edit-group-\(other.id)")
            }
        }
    }

    // MARK: History

    @ViewBuilder private var historyCard: some View {
        if !history.isEmpty || loadFailed {
            PFCard("Edit history", icon: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 12) {
                    if loadFailed { PFParagraph("The edit history could not be loaded.") }
                    ForEach(history.reversed()) { record in historyRow(record) }
                }
            }
            .containerIdentifier("pf-activity-edit-history")
        }
    }

    private func historyRow(_ record: PFEditRecord) -> some View {
        let isActive = doc.isActive(record)
        let isAction = record.spec.op == "undo" || record.spec.op == "ungroup"
        return VStack(alignment: .leading, spacing: 6) {
            Text(record.spec.summary)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(isActive || isAction ? StrandPalette.textPrimary : StrandPalette.textTertiary)
            Text(historyLine(record, isActive: isActive, isAction: isAction))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
            if isActive {
                PFWeekButton529(title: "Undo", isDisabled: runner.isBusy, identifier: "pf-activity-edit-undo-\(record.id)") { Task { await undo(record) } }
            }
        }
    }

    private func historyLine(_ record: PFEditRecord, isActive: Bool, isAction: Bool) -> String {
        var parts: [String] = []
        if record.ts.count >= 10 { parts.append(PFFormat.shortDate(String(record.ts.prefix(10)))) }
        parts.append(record.author == "coach" ? "suggested by the Coach, confirmed by you" : "by you")
        if !isAction { parts.append(isActive ? "in force" : "undone") }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Jobs

    @MainActor private func load() async {
        do {
            doc = PFActivityEdits.parse(try await PFAPI.fetch("api/activity-edits"))
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Stores the preview on the server. The form is cleared only once the server has it; a refusal keeps everything typed.
    @MainActor private func propose() async {
        note = nil
        guard await runner.run(.activityEditPropose, inputs: draft.inputs) != nil else { return }
        draft = PFActivityEditDraft(activityID: activityID, currentType: type, currentName: name, durationS: nil)
        note = "Here is the preview. Nothing is changed until you confirm."
        await load()
    }

    @MainActor private func confirm(_ proposal: PFEditProposal) async {
        note = nil
        if await runner.run(.activityEditConfirm, inputs: PFJobInputs.activityEditConfirm(proposalID: proposal.id)) != nil {
            note = "Applied. The Garmin recording is unchanged and you can undo this below."
            await PFUnified.model.refresh()
        }
        await load()
    }

    @MainActor private func reject(_ proposal: PFEditProposal) async {
        note = nil
        if await runner.run(.activityEditReject, inputs: PFJobInputs.activityEditReject(proposalID: proposal.id)) != nil {
            note = "Dropped. Nothing was changed."
        }
        await load()
    }

    @MainActor private func undo(_ record: PFEditRecord) async {
        note = nil
        if await runner.run(.activityEditUndo, inputs: PFJobInputs.activityEditUndo(editID: record.id)) != nil {
            note = "Undone."
            await PFUnified.model.refresh()
        }
        await load()
    }
}
