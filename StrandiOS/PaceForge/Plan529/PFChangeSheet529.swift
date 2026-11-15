import SwiftUI
import StrandDesign

/// One proposed change (W3): before and after, what the data says, why, what happens if you keep it, Accept and Keep, then the footnote.
/// The sheet looks the change up by its id in the week documents; the Week page remembers the changes it has read so the sheet opens at once.
struct PFChangeSheet529: View {
    let changeId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavRouter
    @StateObject private var lookup = PFChangeLookup529()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch lookup.state {
                case .loading:
                    PFWeekState529(kind: .loading, message: "Loading the change")
                case .missing:
                    PFWeekState529(kind: .empty, message: "This change is no longer waiting for you.")
                case .found(let change, _):
                    Text(change.sheetTitle ?? change.title ?? "Change")
                        .font(LookFont.text(20, weight: .bold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    PFChangeContent529(change: change, onAccepted: { dismiss() }, onKept: { dismiss() },
                                       onTryAnother: nil, onAskCoach: { askCoach(change) })
                }
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Change")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("plan529-change")
        .task { await lookup.load(id: changeId) }
    }

    private func askCoach(_ change: PFPlanWeekDoc.Change) {
        let title = change.sheetTitle ?? change.title ?? "this change"
        PFChatPrefill.shared.text = "About your proposal \"\(title)\": why do you want this change, and what happens if I keep the session as it is?"
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.openCoach() }
    }
}

/// The body of a change, shared by W3 and the answer to Change workout (W5): before and after, the built workout when there is one,
/// warnings in amber, the three short answers, and the buttons.
struct PFChangeContent529: View {
    let change: PFPlanWeekDoc.Change
    let onAccepted: () -> Void
    let onKept: () -> Void
    /// nil on a plain change (the third button is then Ask the coach).
    let onTryAnother: (() -> Void)?
    let onAskCoach: () -> Void

    @StateObject private var decisions = PFWeekDecisions529()

    private var isRequested: Bool { change.requested == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            beforeAfter
            if let detail = change.afterDetail { builtWorkout(detail) }
            if let warnings = change.warnings, !warnings.isEmpty { warningCard(warnings) }
            answers
            buttons
            if let failure = decisions.failure {
                Text(failure)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(PFWeekColor529.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-change-failed")
            }
            if let footnote = change.footnote, !footnote.isEmpty { PFWeekSub529(text: footnote) }
        }
        .containerIdentifier("plan529-change-content")
    }

    // MARK: Parts

    private var beforeAfter: some View {
        HStack(alignment: .center, spacing: 6) {
            side(heading: "Now", side: change.before, id: "plan529-change-before")
            Text("\u{2192}").font(LookFont.text(16, weight: .regular)).foregroundStyle(NoopLook.textTertiary)
            side(heading: "Proposed", side: change.after, id: "plan529-change-after")
        }
    }

    private func side(heading: String, side: PFPlanWeekDoc.Side?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(heading).font(LookFont.text(11, weight: .regular)).foregroundStyle(NoopLook.textTertiary)
            Text(side?.label ?? "")
                .font(LookFont.text(20, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text(side?.sub ?? "")
                .font(LookFont.text(11, weight: .regular))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.row))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func builtWorkout(_ detail: PFPlanWeekDoc.AfterDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(detail.title ?? "")
                    .font(LookFont.text(17, weight: .bold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .accessibilityIdentifier("plan529-change-built-title")
                Spacer(minLength: 6)
                if let label = detail.effortLabel, !label.isEmpty {
                    PFChip(text: label, color: PFWeekColor529.effort(Self.effort(from: label)))
                }
            }
            if let why = detail.why, !why.isEmpty { PFWeekLine529(label: "Why", text: why) }
            if let how = detail.howHard, !how.isEmpty { PFWeekLine529(label: "How hard", text: how) }
            if let todo = detail.do, !todo.isEmpty { PFWeekLine529(label: "Do", text: todo) }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-change-built")
    }

    /// "Easy · 30 min" names its effort first.
    private static func effort(from label: String) -> String {
        let word = label.lowercased()
        if word.hasPrefix("hard") { return "hard" }
        if word.hasPrefix("moderate") { return "moderate" }
        if word.hasPrefix("easy") { return "easy" }
        if word.hasPrefix("race") { return "race" }
        return ""
    }

    private func warningCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PFWeekColor529.amber)
                        .accessibilityHidden(true)
                    Text(warning)
                        .font(LookFont.text(14, weight: .regular))
                        .foregroundStyle(PFWeekColor529.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-change-warning")
                }
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-change-warnings")
    }

    private var answers: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let text = change.dataSays, !text.isEmpty { PFWeekLine529(label: "What the data says", text: text) }
            if let text = change.why, !text.isEmpty { PFWeekLine529(label: "Why this change", text: text) }
            if let text = change.ifKeep, !text.isEmpty { PFWeekLine529(label: "If you keep it", text: text) }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-change-answers")
    }

    private var buttons: some View {
        LookFlowLayout(spacing: 6, lineSpacing: 6) {
            PFWeekButton529(title: change.acceptLabel ?? "Accept", isProminent: true, isDisabled: decisions.isBusy,
                            identifier: "plan529-change-accept") {
                Task { if await decisions.decide(change.id ?? "", accept: true) { onAccepted() } }
            }
            if let onTryAnother {
                PFWeekButton529(title: change.againLabel ?? "Try another", isDisabled: decisions.isBusy,
                                identifier: "plan529-change-again", action: onTryAnother)
                PFWeekButton529(title: change.keepLabel ?? "Keep the original", isDisabled: decisions.isBusy,
                                identifier: "plan529-change-keep") {
                    Task { if await decisions.decide(change.id ?? "", accept: false) { onKept() } }
                }
            } else {
                PFWeekButton529(title: change.keepLabel ?? "Keep", isDisabled: decisions.isBusy, identifier: "plan529-change-keep") {
                    Task { if await decisions.decide(change.id ?? "", accept: false) { onKept() } }
                }
                PFWeekButton529(title: "Ask the coach", isDisabled: decisions.isBusy, identifier: "plan529-change-ask", action: onAskCoach)
            }
        }
    }
}

// MARK: Finding a change

enum PFWeekFetch529 {
    /// One week document, read and decoded; nil when the server does not serve it or it cannot be read.
    static func week(_ isoWeek: String) async -> PFPlanWeekDoc? {
        let fetched = await PFAPI.fetchDoc(PFDocPath529.week(isoWeek))
        guard let data = fetched.data else { return nil }
        return try? PFPlan529Decoder.make().decode(PFPlanWeekDoc.self, from: data)
    }

    static func index() async -> PFPlanWeekIndexDoc? {
        let fetched = await PFAPI.fetchDoc(PFDocPath529.weekIndex)
        guard let data = fetched.data else { return nil }
        return try? PFPlan529Decoder.make().decode(PFPlanWeekIndexDoc.self, from: data)
    }
}

/// The change a sheet was asked to open. The Week page hands over the changes it has read; otherwise the coming weeks are searched.
@MainActor
final class PFChangeLookup529: ObservableObject {
    enum State {
        case loading
        case found(PFPlanWeekDoc.Change, week: String)
        case missing
    }

    @Published private(set) var state: State = .loading

    private static var remembered: [String: (change: PFPlanWeekDoc.Change, week: String)] = [:]

    static func remember(_ doc: PFPlanWeekDoc) {
        for change in doc.changes ?? [] {
            if let id = change.id { remembered[id] = (change, doc.week ?? "") }
        }
    }

    func load(id: String) async {
        if let known = Self.remembered[id] {
            state = .found(known.change, week: known.week)
            return
        }
        guard let index = await PFWeekFetch529.index() else {
            state = .missing
            return
        }
        let weeks = (index.weeks ?? []).filter { $0.state != "finished" }.compactMap { $0.week }
        for week in weeks.prefix(8) {
            guard let doc = await PFWeekFetch529.week(week) else { continue }
            Self.remember(doc)
            if let change = doc.changes?.first(where: { $0.id == id }) {
                state = .found(change, week: week)
                return
            }
        }
        state = .missing
    }
}
