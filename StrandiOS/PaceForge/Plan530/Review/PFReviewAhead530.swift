import SwiftUI
import StrandDesign

/// Screens 1d and 1e: the week ahead. The part the review document carries (headline, the calendar bar, the mix of work) draws at once;
/// the seven days, the hours, the changes waiting and every workout come from the next week's own document, read here. "Accept week" and
/// the change buttons are the Week screens' own answer calls (`PFWeekDecisions529`), so an answer here moves the plan everywhere.
struct PFReviewAhead530: View {
    let week: String
    let ahead: PFWeekReviewDoc530.Ahead?

    @StateObject private var store: PFDocStore529<PFPlanWeekDoc>
    @StateObject private var decisions = PFWeekDecisions529()
    private let hiding = PFHiding()

    init(week: String, ahead: PFWeekReviewDoc530.Ahead?) {
        self.week = week
        self.ahead = ahead
        _store = StateObject(wrappedValue: PFDocStore529<PFPlanWeekDoc>(path: PFDocPath529.week(week)))
    }

    private var number: String { PFReviewFormat530.weekNumber(week) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFReviewSectionTitle530(text: "Week \(number) \u{00B7} the plan")
            if let doc = store.doc { pills(doc) }
            if let headline = ahead?.headline, !headline.isEmpty {
                PFReviewHeadline530(text: headline, identifier: "review530-headline")
            }
            if let ahead, let calendar = ahead.calendar, !calendar.isEmpty { calendarCard(ahead, calendar) }
            switch store.state {
            case .loading:
                PFWeekState529(kind: .loading, message: "Loading week \(number)")
                mix
            case .empty:
                PFWeekState529(kind: .empty, message: "Week \(number) is not ready yet.")
                mix
            case .failed:
                PFWeekState529(kind: .failed, message: "Week \(number) could not be loaded.", retry: { Task { await store.refresh() } })
                mix
            case .loaded(let doc):
                if store.isStale { PFWeekSub529(text: "Showing the copy saved on this phone. PaceForge could not be reached.") }
                strip(doc)
                mix
                if let hours = doc.hours { PFWeekHours529(hours: hours) }
                decide(doc)
                PFReviewWorkouts530(week: week, number: number, doc: doc)
            }
        }
        .task { await store.refreshIfStale() }
        .onReceive(NotificationCenter.default.publisher(for: .pfPlan529Changed)) { _ in
            Task { await store.refresh() }
        }
    }

    // MARK: Where the week sits

    private func pills(_ doc: PFPlanWeekDoc) -> some View {
        var out: [(text: String, color: Color)] = []
        if let pill = doc.phase?.pill { out.append((pill, PFWeekPhase529.color(doc.phase?.key))) }
        if let pill = doc.nextRace?.pill { out.append((pill, NoopLook.textTertiary)) }
        return PFWeekPills529(pills: out)
    }

    /// The bar from today to the race, one stretch per phase, the race a thin tick at the end, and the line that says what it means.
    private func calendarCard(_ ahead: PFWeekReviewDoc530.Ahead, _ calendar: [PFWeekReviewDoc530.Phase]) -> some View {
        let race = ahead.nextRace
        var title = "The season ahead"
        if let name = race?.name, !name.isEmpty {
            title = "From today to \(name)"
            if let date = race?.date, date.count >= 10 { title += " \u{00B7} \(PFFormat.dayTitle(date))" }
            if let goal = race?.goal, !goal.isEmpty { title += " \u{00B7} goal \(goal)" }
        }
        return VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: title)
            calendarBar(calendar, hasRace: race != nil)
                .accessibilityIdentifier("review530-calendar-bar")
            LookFlowLayout(spacing: 12, lineSpacing: 4) {
                ForEach(calendar.indices, id: \.self) { index in
                    HStack(spacing: 5) {
                        Circle().fill(PFReviewFormat530.phaseColor(calendar[index].phase)).frame(width: 8, height: 8)
                        Text(legend(calendar, index))
                            .font(LookFont.text(11.5, weight: .regular))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
            }
            PFReviewReading530(key: "calendar", text: ahead.calendarReading)
        }
        .pfReviewCard530("calendar")
    }

    private func calendarBar(_ calendar: [PFWeekReviewDoc530.Phase], hasRace: Bool) -> some View {
        let days = calendar.map { Double(max($0.days ?? 0, 0)) }
        let total = max(days.reduce(0, +), 1)
        let share = hasRace ? 0.97 : 1.0
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(calendar.indices, id: \.self) { index in
                    Rectangle()
                        .fill(PFReviewFormat530.phaseColor(calendar[index].phase))
                        .frame(width: proxy.size.width * CGFloat(days[index] / total * share))
                }
                if hasRace {
                    Rectangle().fill(PFWeekColor529.red).frame(width: proxy.size.width * 0.03)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Season phases up to the race: " + calendar.map { "\($0.phase ?? "") \($0.days ?? 0) days" }.joined(separator: ", "))
    }

    /// "recover to 24 Nov", "build 25 Nov to 8 Dec", "taper from 9 Dec".
    private func legend(_ calendar: [PFWeekReviewDoc530.Phase], _ index: Int) -> String {
        let entry = calendar[index]
        let name = (entry.phase ?? "").lowercased()
        let from = entry.from.map { PFFormat.shortDate($0) }, to = entry.to.map { PFFormat.shortDate($0) }
        if index == 0, let to { return "\(name) to \(to)" }
        if index == calendar.count - 1, let from { return "\(name) from \(from)" }
        if let from, let to { return "\(name) \(from) to \(to)" }
        return name
    }

    // MARK: The seven days, the mix

    private func strip(_ doc: PFPlanWeekDoc) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "The seven days")
            PFWeekStrip529(days: doc.strip ?? [])
            PFWeekLegend529()
        }
        .pfReviewCard530("days")
    }

    @ViewBuilder private var mix: some View {
        if let entries = ahead?.mix?.filter({ ($0.minutes ?? 0) > 0 }), !entries.isEmpty {
            let top = Double(entries.compactMap { $0.minutes }.max() ?? 1)
            VStack(alignment: .leading, spacing: 10) {
                PFWeekOverline529(text: "The mix \u{00B7} minutes")
                PFHBars530(rows: entries.indices.map { index in
                    PFHBar530(id: index, label: PFReviewFormat530.mixLabel(entries[index].type), value: Double(entries[index].minutes ?? 0),
                              valueText: String(entries[index].minutes ?? 0), color: PFReviewFormat530.mixColor(entries[index].type))
                }, scale: top, labelWidth: 124)
            }
            .pfReviewCard530("mix")
        }
    }

    // MARK: What needs an answer

    @ViewBuilder private func decide(_ doc: PFPlanWeekDoc) -> some View {
        let changes = doc.changes ?? []
        if changes.isEmpty {
            if let line = (doc.decided ?? []).first {
                PFWeekSub529(text: line).accessibilityIdentifier("review530-decided")
            }
            PFWeekSub529(text: "Nothing waits for your answer in week \(number).").accessibilityIdentifier("review530-nothing-waits")
        } else {
            changesCard(changes, decided: doc.decided ?? [])
            PFReviewWideButton530(title: "Accept week \(number)", isDisabled: decisions.isBusy, identifier: "review530-accept-week") {
                Task { await decisions.acceptAll(changes.compactMap { $0.id }) }
            }
        }
    }

    private func changesCard(_ changes: [PFPlanWeekDoc.Change], decided: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PFWeekOverline529(text: changes.count == 1 ? "1 change for you to decide" : "\(changes.count) changes for you to decide")
            ForEach(changes.indices, id: \.self) { index in
                if index > 0 { Divider().overlay(NoopLook.divider) }
                changeRow(changes[index])
            }
            ForEach(decided.indices, id: \.self) { index in
                PFWeekSub529(text: decided[index])
            }
            if let failure = decisions.failure {
                Text(failure)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(PFWeekColor529.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("review530-changes-failed")
            }
        }
        .pfWeekCard()
        .containerIdentifier("review530-changes")
    }

    private func changeRow(_ change: PFPlanWeekDoc.Change) -> some View {
        let id = change.id ?? ""
        let caption = (change.title ?? "").split(separator: ",").first.map(String.init) ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                side(small: caption, big: change.before?.label, sub: change.before?.sub)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .padding(.top, 20)
                    .accessibilityHidden(true)
                side(small: "Coach proposes", big: change.after?.label, sub: change.after?.sub)
            }
            if change.before == nil, change.after == nil, let line = change.oneLine { PFWeekSub529(text: line) }
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                PFWeekButton529(title: change.acceptLabel ?? "Accept", isProminent: true, isDisabled: decisions.isBusy,
                                identifier: "review530-change-accept-\(id)") {
                    Task { await decisions.decide(id, accept: true) }
                }
                PFWeekButton529(title: "Keep as booked", isDisabled: decisions.isBusy, identifier: "review530-change-keep-\(id)") {
                    Task { await decisions.decide(id, accept: false) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review530-change-\(id)")
    }

    private func side(small: String, big: String?, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(small).font(LookFont.text(11.5, weight: .regular)).foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(hiding.text(big ?? "")).font(LookFont.text(20, weight: .bold)).foregroundStyle(NoopLook.textPrimary)
            if let sub, !sub.isEmpty {
                Text(hiding.text(sub)).font(LookFont.text(11.5, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
