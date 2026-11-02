import SwiftUI
import StrandDesign

// "My Plan": this week's plan on Today. A line of "5 DAYS LEFT . 62 % ACCOMPLISHED", a green progress bar, one row per planned
// session with a check or a ring, the next session, and VIEW MY PLAN, which opens the This week screen in the PaceForge tab. It
// is the same card on NOOP Today and on PaceForge Today, read from my-plan.json; nothing here edits the plan. On the Plan tab it is
// `collapsible`: one line (the title and the days-left read-out) that opens the card, and without VIEW MY PLAN, which only re-selects
// the tab it is already on (the week is the section under it).

struct PFMyPlanCard: View {
    let plan: PFMyPlan
    /// Opens the This week screen. Injected so a preview or a test needs no navigation.
    var onOpen: () -> Void = { PFDeepLink.open(.week) }
    /// Whether the title row folds the card to one line, and whether VIEW MY PLAN is drawn.
    var collapsible = false
    var showsOpen = true
    @State private var isExpanded: Bool

    init(plan: PFMyPlan, onOpen: @escaping () -> Void = { PFDeepLink.open(.week) }, collapsible: Bool = false, showsOpen: Bool = true) {
        self.plan = plan
        self.onOpen = onOpen
        self.collapsible = collapsible
        self.showsOpen = showsOpen
        _isExpanded = State(initialValue: !collapsible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleRow
            if isExpanded { details }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.tile))
        .containerIdentifier("pf-my-plan")
    }

    @ViewBuilder private var titleRow: some View {
        if collapsible {
            Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("MY PLAN")
                        .lookCaps(13)
                        .foregroundStyle(NoopLook.textPrimary)
                    Spacer(minLength: 8)
                    if !isExpanded {
                        Text(plan.headerText)
                            .lookCaps(11)
                            .foregroundStyle(NoopLook.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")
            .accessibilityIdentifier("pf-plan-toggle")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("MY PLAN")
                    .lookCaps(13)
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                if let name = plan.planName {
                    Text(plan.planPhase.map { "\(name) \u{00B7} \($0)" } ?? name)
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.headerText)
                    .lookCaps(12)
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityIdentifier("pf-plan-header")
                progressBar
            }
            VStack(spacing: 0) {
                ForEach(plan.items) { row in
                    planRow(row)
                    if row.id != plan.items.last?.id {
                        Rectangle().fill(NoopLook.divider).frame(height: 1)
                    }
                }
            }
            .containerIdentifier("pf-plan-rows")
            if let next = plan.next {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("NEXT")
                        .lookCaps(10.5)
                        .foregroundStyle(NoopLook.textTertiary)
                    Text(next.label)
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(next.detailText)
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-plan-next")
            }
            if showsOpen {
                Button(action: onOpen) {
                    Text("VIEW MY PLAN")
                        .lookCaps(13)
                        .foregroundStyle(NoopLook.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.rowRadius, style: .continuous).fill(NoopLook.row))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this week in PaceForge")
                .accessibilityIdentifier("pf-plan-view")
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NoopLook.track)
                Capsule()
                    .fill(NoopLook.trendUp)
                    .frame(width: max(geo.size.width * CGFloat(plan.progress), plan.progress > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan progress")
        .accessibilityValue("\(plan.pctAccomplished ?? Safe.int((plan.progress * 100))) percent")
        .accessibilityIdentifier("pf-plan-progress")
    }

    private func symbol(_ status: String) -> (name: String, color: Color) {
        switch status {
        case "done": return ("checkmark.circle.fill", NoopLook.trendUp)
        case "partial": return ("circle.lefthalf.filled", NoopLook.trendDown)
        case "missed": return ("xmark.circle", NoopLook.textTertiary)
        case "today": return ("circle.dotted", NoopLook.effort)
        default: return ("circle", NoopLook.textMuted)
        }
    }

    private func statusWord(_ status: String) -> String {
        switch status {
        case "done": return "done"
        case "partial": return "cut short"
        case "missed": return "missed"
        case "today": return "today"
        default: return "upcoming"
        }
    }

    private func planRow(_ row: PFPlanItem) -> some View {
        let mark = symbol(row.status)
        return HStack(spacing: 12) {
            Image(systemName: mark.name)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(mark.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(LookFont.text(15, weight: .medium))
                    .foregroundStyle(row.status == "missed" ? NoopLook.textTertiary : NoopLook.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.detailText.isEmpty {
                    Text(row.detailText)
                        .font(LookFont.text(12.5, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label), \(row.detailText), \(statusWord(row.status))")
        .accessibilityIdentifier("pf-plan-row-\(row.index)")
    }
}

/// NOOP Today's My Plan card: reads the shared store, so it needs no PaceForge tab. Nothing when no plan is published. On Today
/// (`showsAdjust`) the Adjust today card sits under it while a session is planned for today, and the Niggles row below that.
struct PFMyPlanStoreHost: View {
    @ObservedObject private var store = PFPhase4Store.shared
    private let showsAdjust: Bool
    private let isOnPlanTab: Bool

    /// `isOnPlanTab`: the card sits on the Plan tab itself, so it folds to one line and has no VIEW MY PLAN (it would only re-select Plan).
    init(showsAdjust: Bool = false, isOnPlanTab: Bool = false) {
        self.showsAdjust = showsAdjust
        self.isOnPlanTab = isOnPlanTab
    }

    var body: some View {
        Group {
            if let plan = store.docs.myPlan.value {
                VStack(spacing: 12) {
                    PFMyPlanCard(plan: plan, collapsible: isOnPlanTab, showsOpen: !isOnPlanTab)
                    if showsAdjust, plan.items.contains(where: { $0.status == "today" }) {
                        PFAdjustTodayCard()
                    }
                    if showsAdjust { PFNiggleEntryCard() }
                }
            }
        }
        .task { await store.refreshIfStale() }
    }
}

#if DEBUG
#Preview("My Plan") {
    PFMyPlanCard(plan: PFPhase4Sample.plan, onOpen: {})
        .padding(16)
        .frame(width: 402)
        .lookScreenBackground()
        .preferredColorScheme(.dark)
}
#endif
