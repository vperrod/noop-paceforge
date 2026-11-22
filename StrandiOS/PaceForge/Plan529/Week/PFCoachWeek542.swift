import SwiftUI
import StrandDesign

// The coach's TrueCoach week on the iPhone (build 542): the Coach week card on Plan > Week, what a coach-assigned session shows on its week
// card and in its sheet, and the Weekly rhythm card in Plan settings. The words and the parsing are Foundation-only in PaceForgeTrueCoach.swift.

/// `GET api/truecoach-status`, kept on the phone like the watch status: one copy for every card that asks.
@MainActor
final class PFTrueCoachStore542: ObservableObject {
    static let shared = PFTrueCoachStore542()

    @Published private(set) var status: PFTrueCoachStatus?
    /// The shown status is the saved copy because the server could not be asked.
    @Published private(set) var isStale = false

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    /// Loads again unless the last good load is under `maxAge` seconds old.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        if let lastFetch, status != nil, !isStale, Date().timeIntervalSince(lastFetch) < maxAge { return }
        await refresh()
    }

    /// Overlapping callers share the load already running.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await load()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func load() async {
        guard PFAPI.isConfigured else { return }
        let fetched = await PFAPI.fetchDoc(PFDocPath529.trueCoachStatus)
        guard let data = fetched.data else {
            // Not served (a PaceForge without the TrueCoach import): no card. Not asked: keep what is on screen.
            if !fetched.failed { status = nil }
            isStale = fetched.failed && status != nil
            return
        }
        guard let parsed = PFTrueCoachStatus.parse(data) else { return }
        status = parsed
        isStale = fetched.failed
        if !fetched.failed { lastFetch = Date() }
    }
}

// MARK: Coach session

/// On a coach-assigned session (week card and session sheet): the line that it must be done this week, or, when it was skipped, that it counts as
/// missed with an Undo. Nothing for any other session.
struct PFCoachSessionNote542: View {
    let item: PFPlanWeekDoc.Item
    let idPrefix: String

    @ObservedObject private var store = PFTrueCoachStore542.shared
    @StateObject private var tracker = PFJobTracker()

    private var isSkipped: Bool {
        PFCoachSession.isSkipped(itemFlag: item.skippedMandatory, row: store.status?.weekRow(sessionID: item.sessionId))
    }
    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        if item.coachAssigned == true {
            VStack(alignment: .leading, spacing: 6) {
                if isSkipped {
                    HStack(alignment: .center, spacing: 10) {
                        Label(PFCoachSession.skippedLine, systemImage: "xmark.circle")
                            .font(LookFont.text(13, weight: .medium))
                            .foregroundStyle(PFWeekColor529.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("\(idPrefix)-skipped")
                        Spacer(minLength: 6)
                        PFWeekButton529(title: "Undo", isDisabled: isBusy || item.sessionId == nil, identifier: "\(idPrefix)-undo") {
                            Task { await undo() }
                        }
                    }
                } else if item.mandatory == true {
                    Label(PFCoachSession.mustLine(weekStart: item.weekStart), systemImage: "calendar")
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(idPrefix)-must")
                }
                if case .failed(let message) = tracker.phase { PFWeekSub529(text: message) }
            }
            .task { await store.refreshIfStale() }
        }
    }

    /// The existing `calendar-edit` restore.
    @MainActor private func undo() async {
        guard let inputs = PFJobInputs.calendarRestore(sessionID: item.sessionId) else { return }
        if case .success = await tracker.run(.calendarEdit, inputs: inputs) {
            await store.refresh()
            await PFUnified.model.refresh()
            NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        }
    }
}

/// The coach's prescription as he wrote it, readable in full; a long one scrolls inside its card.
struct PFCoachDetailsCard542: View {
    let details: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PFWeekOverline529(text: PFCoachSession.detailsTitle)
            if PFCoachSession.needsScroll(details) {
                ScrollView { text }
                    .frame(height: 320)
            } else {
                text
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-session-coach-details")
    }

    private var text: some View {
        Text(details)
            .font(LookFont.text(14, weight: .regular))
            .foregroundStyle(NoopLook.textPrimary)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("plan529-session-coach-details-text")
    }
}

// MARK: Coach week card (Plan > Week)

/// What was read from TrueCoach and when, a Sync now button, the last read's error in plain words and what the replan did around the coach's
/// sessions (with Undo). Nothing until the server serves `api/truecoach-status`.
struct PFCoachWeekCard542: View {
    @ObservedObject private var store = PFTrueCoachStore542.shared
    @StateObject private var tracker = PFJobTracker()
    @State private var note: String?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        Group {
            if let status = store.status { card(status) }
        }
        .task { await store.refreshIfStale() }
        .onReceive(NotificationCenter.default.publisher(for: .pfPlan529Changed)) { _ in
            Task { await store.refresh() }
        }
    }

    private func card(_ status: PFTrueCoachStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: PFTrueCoachWording.title)
            Text(PFTrueCoachWording.count(status))
                .font(LookFont.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .accessibilityIdentifier("plan529-coachweek-count")
            PFWeekSub529(text: store.isStale
                         ? PFTrueCoachWording.lastSync(status.lastSync) + ". PaceForge could not be reached, so this is the copy saved on this phone."
                         : PFTrueCoachWording.lastSync(status.lastSync))
                .accessibilityIdentifier("plan529-coachweek-last")
            if let error = PFTrueCoachWording.error(status) {
                Text(error)
                    .font(LookFont.text(13, weight: .regular))
                    .foregroundStyle(PFWeekColor529.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-coachweek-error")
            }
            if let replan = status.replan, !replan.isEmpty { replanBlock(replan) }
            HStack(spacing: 10) {
                PFWeekButton529(title: isBusy ? "Reading\u{2026}" : PFTrueCoachWording.syncButton, isProminent: true, isDisabled: isBusy,
                                identifier: "plan529-coachweek-sync") {
                    Task { await sync() }
                }
                Spacer(minLength: 0)
            }
            footer
        }
        .pfWeekCard()
        .containerIdentifier("plan529-coachweek")
    }

    @ViewBuilder private func replanBlock(_ replan: PFTrueCoachStatus.Replan) -> some View {
        PFDivider529()
        if let removed = PFTrueCoachWording.removed(replan) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(removed)
                        .font(LookFont.text(13.5, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-coachweek-removed")
                    if let kept = PFTrueCoachWording.kept(replan) { PFWeekSub529(text: kept) }
                }
                Spacer(minLength: 6)
                PFWeekButton529(title: PFTrueCoachWording.undoButton, isDisabled: isBusy, identifier: "plan529-coachweek-undo") {
                    Task { await undo() }
                }
            }
        }
        if !replan.conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                PFWeekOverline529(text: PFTrueCoachWording.checkThese)
                PFWeekSub529(text: "These booked classes overlap your coach's sessions.")
                ForEach(Array(replan.conflicts.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(LookFont.text(13.5, weight: .regular))
                        .foregroundStyle(PFWeekColor529.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("plan529-coachweek-check")
        }
        ForEach(Array(replan.warnings.enumerated()), id: \.offset) { _, line in PFWeekSub529(text: line) }
    }

    @ViewBuilder private var footer: some View {
        switch tracker.phase {
        case .sending, .working:
            PFWeekSub529(text: "Reading your TrueCoach plan. This can take a few minutes.")
        case .failed(let message):
            Text(message)
                .font(LookFont.text(12.5, weight: .regular))
                .foregroundStyle(PFWeekColor529.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plan529-coachweek-failed")
        case .done:
            if let note { PFWeekSub529(text: note).accessibilityIdentifier("plan529-coachweek-result") }
        case .idle:
            EmptyView()
        }
    }

    @MainActor private func sync() async {
        note = nil
        if case .success = await tracker.run(.truecoachSync, inputs: PFJobInputs.truecoachSync()) {
            note = "Your coach's week is read."
            await changed()
        }
    }

    @MainActor private func undo() async {
        note = nil
        if case .success = await tracker.run(.truecoachReplanUndo, inputs: PFJobInputs.truecoachReplanUndo()) {
            note = "Put back."
            await changed()
        }
    }

    @MainActor private func changed() async {
        await store.refresh()
        await PFUnified.model.refresh()
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
    }
}

// MARK: Weekly rhythm (Plan settings)

/// The Sunday schedule in words, and when the TrueCoach week was last read when the server says.
struct PFWeeklyRhythmCard542: View {
    @ObservedObject private var store = PFTrueCoachStore542.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PFOver529(text: PFWeeklyRhythm.title)
            Text(PFWeeklyRhythm.text)
                .font(LookFont.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings-rhythm-text")
            if let last = PFWeeklyRhythm.lastRead(store.status?.lastSync) {
                Text(last)
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityIdentifier("settings-rhythm-last")
            }
        }
        .planCard529()
        .containerIdentifier("settings-rhythm")
        .task { await store.refreshIfStale() }
    }
}
