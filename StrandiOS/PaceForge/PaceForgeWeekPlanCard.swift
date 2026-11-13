import SwiftUI
import UIKit
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
    /// The chart PNGs of the report by name, fetched with the same token as the documents; a name missing here has not loaded
    /// (yet) or the server did not serve it.
    @Published private(set) var chartImages: [String: UIImage] = [:]
    @Published private(set) var chartsLoading = false
    private var chartsLoadedAt: String?

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
        await loadCharts()
    }

    /// The charts are redrawn by the server with each report (`charts_at`), so they are fetched again only when that changes
    /// or one is still missing.
    private func loadCharts() async {
        guard let weekly, !weekly.charts.isEmpty else { return }
        let stamp = weekly.chartsAt ?? ""
        let missing = weekly.charts.filter { chartImages[$0] == nil }
        guard stamp != chartsLoadedAt || !missing.isEmpty else { return }
        chartsLoading = true
        defer { chartsLoading = false }
        var fresh: [String: UIImage] = stamp == chartsLoadedAt ? chartImages : [:]
        for key in weekly.charts {
            if let data = try? await PFAPI.fetch(PFWeekPlan.chartPath(key)), let image = UIImage(data: data) { fresh[key] = image }
        }
        chartImages = fresh
        if fresh.count == weekly.charts.count { chartsLoadedAt = stamp }
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
            out.append(PFRacePack(date: date, name: event.name, markdown: text, isHyrox: PFHyroxEventKind.isHyrox(name: event.name, type: event.type)))
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

    private var isDesigned: Bool { store.weekly?.sections.isEmpty == false }

    var body: some View {
        if PFAPI.isConfigured {
            PFCard(title: isDesigned ? "Your week, and the plan for next week" : "Week report and next week's plan", icon: "calendar", trailing: {
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
            if let weekly = store.weekly, !weekly.sections.isEmpty {
                sectionsView(weekly)
            } else {
                // A server without the report sections (before build 513's server): the whole report as one text.
                if !store.proposals.isEmpty { proposalsSection }
                if let weekly = store.weekly, !weekly.contentMD.isEmpty {
                    PFWeekMarkdown(text: weekly.contentMD)
                }
            }
        }
    }

    @ViewBuilder private func sectionsView(_ weekly: PFWeekReport) -> some View {
        // Proposals belong inside the plan section; with no plan section they would vanish, so they lead the card instead.
        if !store.proposals.isEmpty && !weekly.sections.contains(where: { $0.kind == .plan }) { proposalsSection }
        ForEach(weekly.sections) { section in
            PFDisclosure(title: section.title, intro: section.intro, startsOpen: section.open, nested: false, id: section.id) {
                switch section.kind {
                case .summary:
                    PFSummaryBody(weekly: weekly)
                case .plan:
                    PFPlanBody(section: section, proposals: store.proposals, onAsk: onAsk)
                case .charts:
                    PFChartsBody(keys: weekly.charts)
                case .md:
                    PFWeekMarkdown(text: section.md)
                }
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

// MARK: Report sections

/// A heading that opens and closes its content: the title, the one-line intro under it and a chevron. `nested` is the smaller
/// day-level version inside a section.
struct PFDisclosure<Content: View>: View {
    let title: String
    let intro: String?
    let nested: Bool
    let id: String
    @ViewBuilder let content: () -> Content
    @State private var isOpen: Bool

    init(title: String, intro: String? = nil, startsOpen: Bool, nested: Bool, id: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.intro = intro.flatMap { $0.isEmpty ? nil : $0 }
        self.nested = nested
        self.id = id
        self.content = content
        _isOpen = State(initialValue: startsOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { isOpen.toggle() } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(nested ? StrandFont.subhead.weight(.semibold) : StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let intro {
                            Text(intro)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.scaled(12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(isOpen ? "Expanded" : "Collapsed"))
            .accessibilityIdentifier("coach-week-section-\(id)")
            if isOpen { content() }
        }
        .padding(nested ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(nested ? StrandPalette.surfaceRaised : StrandPalette.surfaceInset))
    }
}

/// The key numbers as tiles, what held the week back, and the one thing not to do.
private struct PFSummaryBody: View {
    let weekly: PFWeekReport

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let tiles = weekly.summary.map(PFWeekPlan.summaryTiles) ?? []
        let notToDo = weekly.sections.first { $0.id == "review" }.flatMap { PFWeekPlan.oneThingNotToDo($0.md) }
        VStack(alignment: .leading, spacing: 14) {
            if !tiles.isEmpty {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in tileView(tile) }
                }
            }
            if !weekly.limiters.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What held you back")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    ForEach(Array(weekly.limiters.enumerated()), id: \.offset) { _, limiter in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\u{2022}")
                            Text(limiter).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
            if let notToDo {
                VStack(alignment: .leading, spacing: 6) {
                    Label("One thing not to do", systemImage: "exclamationmark.triangle")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(PFColor.warning)
                    PFMarkdown(text: notToDo)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PFColor.warning.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PFColor.warning.opacity(0.5), lineWidth: 1))
                .accessibilityIdentifier("coach-week-not-to-do")
            }
        }
    }

    private func tileView(_ tile: PFSummaryTile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(tile.value)
                .font(StrandFont.rounded(24))
                .foregroundStyle(StrandPalette.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(tile.note ?? " ")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceRaised))
        .accessibilityElement(children: .combine)
    }
}

/// Next week day by day, with each pending proposal inside the day it changes and the rest at the end.
private struct PFPlanBody: View {
    let section: PFWeekSection
    let proposals: [PFPendingProposal]
    let onAsk: (String) -> Void

    var body: some View {
        let plan = PFWeekPlan.planDays(section.md)
        let placed = PFWeekPlan.assign(proposals, to: plan.days)
        VStack(alignment: .leading, spacing: 10) {
            if !plan.preamble.isEmpty { PFWeekMarkdown(text: plan.preamble) }
            ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                PFDisclosure(title: day.title, startsOpen: true, nested: true, id: "\(section.id)-day-\(index)") {
                    VStack(alignment: .leading, spacing: 10) {
                        if !day.body.isEmpty { PFWeekMarkdown(text: day.body) }
                        ForEach(placed.byDay[index]) { proposal in
                            PFProposalView(proposal: proposal, onAsk: onAsk, showsDay: false)
                        }
                    }
                }
            }
            if !placed.unmatched.isEmpty {
                Text("Other changes the coach proposes")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityIdentifier("coach-week-proposals")
                ForEach(placed.unmatched) { proposal in
                    PFProposalView(proposal: proposal, onAsk: onAsk)
                }
            }
        }
    }
}

/// The report's charts: each PNG with its caption.
private struct PFChartsBody: View {
    let keys: [String]
    @ObservedObject private var store = PFWeekPlanStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(keys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 6) {
                    Text(PFWeekPlan.chartCaption(key))
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let image = store.chartImages[key] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel(Text(PFWeekPlan.chartCaption(key)))
                    } else if store.chartsLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        Text("This chart is not available right now.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }
}

struct PFProposalView: View {
    let proposal: PFPendingProposal
    let onAsk: (String) -> Void
    /// False inside a plan day, which already says the day.
    var showsDay = true

    @ObservedObject private var store = PFWeekPlanStore.shared

    private var isSending: Bool { store.deciding.contains(proposal.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsDay, let day = proposal.dayLabel {
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
                if pack.isHyrox { PFOpenHyroxButton() }
            }
        }
        .accessibilityIdentifier("coach-race-plan-\(pack.date)")
    }
}

// MARK: Markdown with tables that scroll

/// The coach's markdown. Tables sit in a sideways scroll view at a width that fits their columns, so a wide table scrolls instead of
/// running off the card or squeezing its words one letter wide.
struct PFWeekMarkdown: View {
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
                    .font(StrandFont.scaled(14, weight: .semibold))
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
                    .font(StrandFont.scaled(12, weight: .semibold))
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
