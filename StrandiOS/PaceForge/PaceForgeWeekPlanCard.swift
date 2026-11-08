import SwiftUI
import StrandDesign

// The Coach screen's week card (`PFWeekPlanCard`) and its race plans (`PFRacePackCards`): what the coach wrote for the week, why it wants
// each change to the plan, and Accept / Reject / Ask the coach on every proposal. The parsing and wording are in PaceForgeWeekPlan.swift.

/// A question the athlete asked from a proposal, waiting for the chat box on the Coach screen to take it into its draft.
@MainActor
final class PFChatPrefill: ObservableObject {
    static let shared = PFChatPrefill()

    /// The chat card on the Coach screen: where "Ask the coach about this" scrolls to.
    static let scrollID = "coach-chat"

    @Published var text: String?
}

@MainActor
final class PFWeekPlanStore: ObservableObject {
    static let shared = PFWeekPlanStore()

    static let weeklyPath = "data/weekly.json"
    static let pendingPath = "data/pending-changes.json"
    static let eventsPath = "data/events.json"

    enum Phase: Equatable { case loading, loaded, failed }

    @Published private(set) var weekly: PFWeekReport?
    @Published private(set) var proposals: [PFPendingProposal] = []
    @Published private(set) var racePacks: [PFRacePack] = []
    @Published private(set) var phase: Phase = .loading
    /// Why a decision was not saved, by proposal id.
    @Published private(set) var notes: [String: String] = [:]
    @Published private(set) var deciding: Set<String> = []

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?
    /// Decided this session: a load that started before the answer must not bring them back.
    private var decided: Set<String> = []

    func refreshIfStale() async {
        if let lastFetch, phase == .loaded, Date().timeIntervalSince(lastFetch) < 60 { return }
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
        guard PFAPI.isConfigured else {
            phase = .loaded
            return
        }
        async let weeklyDoc = PFAPI.fetchDoc(Self.weeklyPath)
        async let pendingDoc = PFAPI.fetchDoc(Self.pendingPath)
        async let eventsDoc = PFAPI.fetchDoc(Self.eventsPath)
        let (weeklyResult, pendingResult, eventsResult) = await (weeklyDoc, pendingDoc, eventsDoc)

        // A document the server could not be asked for keeps what is on screen; one it does not serve (404) leaves its part empty.
        let parsedWeekly = PFWeekPlan.weekly(weeklyResult.data)
        if weeklyResult.failed {
            if weekly == nil { weekly = parsedWeekly }
        } else if weekly != parsedWeekly {
            weekly = parsedWeekly
        }
        if !pendingResult.failed {
            let fresh = PFWeekPlan.proposals(pendingResult.data).filter { !decided.contains($0.id) }
            if proposals != fresh { proposals = fresh }
        }
        if !eventsResult.failed {
            let packs = await loadRacePacks(PFWeekPlan.upcomingEvents(eventsResult.data, today: PFFormat.isoString(Date())))
            if racePacks != packs { racePacks = packs }
        }

        if weeklyResult.failed && pendingResult.failed && eventsResult.failed {
            if weekly == nil && proposals.isEmpty { phase = .failed }
        } else {
            lastFetch = Date()
            phase = .loaded
        }
    }

    private func loadRacePacks(_ events: [PFEventRow]) async -> [PFRacePack] {
        var out: [PFRacePack] = []
        var seen: Set<String> = []
        for event in events {
            let date = String(event.date.prefix(10))
            guard seen.insert(date).inserted else { continue }
            let doc = await PFAPI.fetchDoc("data/race-packs/\(date).md")
            guard let data = doc.data, let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            out.append(PFRacePack(date: date, name: event.name, markdown: text))
        }
        return out
    }

    /// Accepts or rejects one proposal with the answer the Needs you card sends. The proposal leaves the card when the server took it;
    /// otherwise it stays, with the reason in `notes`.
    func decide(_ proposal: PFPendingProposal, accept: Bool) async {
        guard !deciding.contains(proposal.id) else { return }
        deciding.insert(proposal.id)
        notes[proposal.id] = nil
        defer { deciding.remove(proposal.id) }

        let model = PFUnified.model
        let answer = PFNeedsAnswer.proposal(id: proposal.id, accept: accept)
        if let item = PFEasyModeJobs.item(forProposal: proposal.id, in: model.snapshot?.needsYou ?? []) {
            await model.submitAnswer(answer, for: item)
            if let note = model.needsNotes[item.id] {
                notes[proposal.id] = note
                return
            }
        } else {
            // The Needs you list does not hold it (not loaded yet, or built from an older file): same endpoint, same body.
            var body = answer.body
            body["key"] = "ios-" + UUID().uuidString.lowercased()
            let outcome: PFAnswerOutcome
            do {
                let reply = try await PFAPI.postAnswer(body)
                outcome = PFAnswerOutcome.from(status: reply.status, data: reply.data)
            } catch {
                outcome = .unreachable
            }
            guard outcome.isSaved else {
                notes[proposal.id] = outcome.message
                return
            }
            await model.refresh()
        }
        decided.insert(proposal.id)
        proposals.removeAll { $0.id == proposal.id }
    }
}

// MARK: Week card

struct PFWeekPlanCard: View {
    /// Puts the question in the chat box and scrolls to it.
    let onAsk: (String) -> Void

    @ObservedObject private var store = PFWeekPlanStore.shared

    var body: some View {
        if PFAPI.isConfigured {
            PFCard(title: "Week report and next week's plan", icon: "calendar", trailing: {
                Text(store.weekly?.periodLabel ?? "")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }) {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
            }
            .accessibilityIdentifier("coach-week-plan")
        }
    }

    @ViewBuilder private var content: some View {
        if store.phase == .loading && store.weekly == nil && store.proposals.isEmpty {
            ProgressView()
        } else if store.phase == .failed {
            Text("The week report could not be loaded")
                .font(StrandFont.subhead)
                .foregroundStyle(PFColor.warning)
        } else if store.weekly == nil && store.proposals.isEmpty {
            Text("The coach has not written a week report yet.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        } else {
            if let weekly = store.weekly {
                if !weekly.headline.isEmpty {
                    Text(weekly.headline)
                        .font(StrandFont.body.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !store.proposals.isEmpty { proposalsSection }
            if let weekly = store.weekly, !weekly.contentMD.isEmpty {
                PFWeekMarkdown(text: weekly.contentMD)
            }
        }
    }

    private var proposalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(PFWeekPlan.cardTitle(store.proposals.count))
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityIdentifier("coach-week-proposals")
            ForEach(store.proposals) { proposal in
                PFProposalView(proposal: proposal, onAsk: onAsk)
            }
        }
    }
}

private struct PFProposalView: View {
    let proposal: PFPendingProposal
    let onAsk: (String) -> Void

    @ObservedObject private var store = PFWeekPlanStore.shared

    private var isSending: Bool { store.deciding.contains(proposal.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let day = proposal.dayLabel {
                Text(day)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Text(proposal.title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !proposal.explanation.isEmpty {
                PFMarkdown(text: proposal.explanation)
            }
            ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, change in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\u{2022}")
                    Text(change.plainWords)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            }
            HStack(spacing: 10) {
                button("Accept", prominent: true, id: "coach-proposal-accept-\(proposal.id)") { decide(true) }
                button("Reject", prominent: false, id: "coach-proposal-reject-\(proposal.id)") { decide(false) }
            }
            Button("Ask the coach about this") { onAsk(proposal.askPrompt) }
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
                .buttonStyle(.plain)
                .frame(minHeight: 32)
                .accessibilityIdentifier("coach-proposal-ask-\(proposal.id)")
            if let note = store.notes[proposal.id] {
                Label(note, systemImage: "exclamationmark.circle")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
    }

    private func button(_ title: String, prominent: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.subhead.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? StrandPalette.accent : StrandPalette.textSecondary)
        .disabled(isSending)
        .accessibilityIdentifier(id)
    }

    private func decide(_ accept: Bool) {
        Task { @MainActor in await store.decide(proposal, accept: accept) }
    }
}

// MARK: Race plans

struct PFRacePackCards: View {
    @ObservedObject private var store = PFWeekPlanStore.shared

    var body: some View {
        // A Group, not a stack: the column it joins spaces its children, and an empty stack would still add a gap.
        Group {
            ForEach(store.racePacks) { pack in PFRacePackCard(pack: pack) }
        }
    }
}

private struct PFRacePackCard: View {
    let pack: PFRacePack
    @State private var showsAll = false

    var body: some View {
        let section = PFWeekPlan.firstSection(pack.markdown)
        PFCard("Race plan \u{00B7} \(pack.name) \u{00B7} \(PFFormat.shortDate(pack.date))", icon: "flag.checkered") {
            VStack(alignment: .leading, spacing: 10) {
                PFWeekMarkdown(text: showsAll ? pack.markdown : section.text)
                if section.hasMore {
                    Button(showsAll ? "Show less" : "Show the full race plan") { showsAll.toggle() }
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .buttonStyle(.plain)
                        .frame(minHeight: 32)
                        .accessibilityIdentifier("coach-race-plan-more-\(pack.date)")
                }
            }
        }
        .accessibilityIdentifier("coach-race-plan-\(pack.date)")
    }
}

// MARK: Markdown with tables that scroll

/// The coach's markdown. Tables sit in a sideways scroll view at a width that fits their columns, so a wide table scrolls instead of
/// running off the card or squeezing its words one letter wide.
private struct PFWeekMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(PFWeekPlan.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let markdown):
                    PFMarkdown(text: markdown)
                case .table(let markdown, let columns):
                    ScrollView(.horizontal, showsIndicators: true) {
                        PFMarkdown(text: markdown)
                            .frame(width: CGFloat(max(columns * 110, 300)), alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: Today

/// Today's one row for every open proposal: the count and where to read why.
struct PFProposalsRow: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
                Text(PFWeekPlan.todayLine(count))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("Read why")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityLabel(Text("\(PFWeekPlan.todayLine(count)). Read why"))
        .accessibilityHint(Text("Opens the Coach"))
        .accessibilityIdentifier("pf-proposals-row")
    }
}
