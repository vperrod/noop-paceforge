import SwiftUI
import StrandDesign

// The monthly performance report, in the look: a switch between the last full month and the month so far, one row per score
// (Charge, Effort, Rest, weight, fitness) with its figure, the month before it, a triangle and the change, the movers with
// what moved them, the goals and next month's focus. Everything is read from monthly-report.json; each row says whose series
// it is (the strap's, or Garmin's when the strap has too few days), and the two are never blended.

struct PFMonthlyReportScreen: View {
    @ObservedObject private var store = PFPhase4Store.shared

    var body: some View {
        PFDocScreen(title: "Monthly report", identifier: "pf-monthly") {
            PFDocStateView(state: store.docs.monthlyReport, didLoad: store.didLoad, title: "Monthly report", icon: "calendar",
                           identifier: "pf-monthly") { report, item in
                PFMonthlyReportBody(report: report, item: item)
            }
        }
    }
}

struct PFMonthlyReportBody: View {
    let report: PFMonthlyReport
    let item: PFIntelItem

    @State private var periodID: String?
    private let hiding = PFHiding()

    private var shownID: String {
        if let periodID, report.period(periodID) != nil { return periodID }
        return report.period("last_full") != nil ? "last_full" : (report.periods.first?.id ?? "")
    }

    private var period: PFMonthPeriod? { report.period(shownID) }

    private func segmentTitle(_ id: String) -> String {
        switch id {
        case "last_full": return "LAST MONTH"
        case "month_to_date": return "MONTH TO DATE"
        default: return (report.period(id)?.label ?? id).uppercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if report.periods.count > 1 {
                LookSegmented(options: report.periods.map(\.id), selection: Binding(get: { shownID }, set: { periodID = $0 }),
                              identifier: "pf-monthly-period", title: segmentTitle)
                    .frame(height: 44)
            }
            if let period {
                header(period)
                rows(period)
                movers(period)
            }
            if !report.goals.isEmpty {
                PFRuleLabel("GOALS")
                ForEach(report.goals) { goal in goalCard(goal) }
            }
            if !report.focus.isEmpty {
                PFRuleLabel("FOCUS FOR NEXT MONTH")
                ForEach(report.focus) { focus in focusCard(focus) }
            }
            Text("Each score is the strap's when it has 10 or more days in both months, else the Garmin-built score named on its row. A change under 2 % is called steady.")
                .font(LookFont.text(12.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            PFIntelFootnote(item: item)
        }
        .containerIdentifier("pf-monthly-body")
    }

    // MARK: Header and rows

    private func header(_ period: PFMonthPeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(period.label)
                .font(LookFont.text(24, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            let detail = [period.days.map { "\($0) days" }, period.comparedWith.map { "compared with \($0)" }]
                .compactMap { $0 }.joined(separator: " \u{00B7} ")
            if !detail.isEmpty {
                Text(detail)
                    .font(LookFont.text(13.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("pf-monthly-header")
    }

    private func hideKind(_ key: String) -> PFRedact.Kind? {
        switch key {
        case "charge", "effort", "rest": return .scores
        case "weight": return .body
        default: return nil
        }
    }

    private func shown(_ text: String, key: String) -> String {
        guard let kind = hideKind(key) else { return text }
        return hiding.shown(text, kind)
    }

    private func tone(_ tone: PFMonthTone) -> LookTodayMark.Tone {
        switch tone {
        case .good: return .favourable
        case .bad: return .unfavourable
        case .neutral: return .neutral
        }
    }

    private func rows(_ period: PFMonthPeriod) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(period.rows.enumerated()), id: \.element.id) { index, row in
                monthRow(row, comparedWith: period.comparedWith)
                if index < period.rows.count - 1 {
                    Rectangle().fill(NoopLook.divider).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-monthly-rows")
    }

    private func monthRow(_ row: PFMonthRow, comparedWith: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .lookCaps(12.5)
                        .foregroundStyle(NoopLook.textPrimary)
                    if let series = row.seriesLabel {
                        Text(series)
                            .font(LookFont.text(11.5, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                if row.hasData, let current = row.current {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(shown(PFMonthlyFormat.valueText(row, current.value), key: row.key))
                            .font(LookFont.numeral(24))
                            .foregroundStyle(NoopLook.textPrimary)
                        if let mark = row.mark {
                            LookTriangleMark(LookTodayMark(pointsUp: mark.pointsUp, tone: tone(mark.tone)))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
            if row.hasData {
                HStack(spacing: 8) {
                    if let delta = PFMonthlyFormat.deltaText(row, comparedWith: comparedWith) {
                        Text(shown(delta, key: row.key))
                            .font(LookFont.text(13, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                    }
                    if let chip = PFMonthlyFormat.chipText(row) {
                        PFChip(text: chip, color: chipColor(row))
                    }
                    Spacer(minLength: 0)
                    if let previous = row.previous {
                        Text("was \(shown(PFMonthlyFormat.valueText(row, previous.value), key: row.key))")
                            .font(LookFont.numeralRegular(13))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
            } else {
                Text(row.reason ?? "Not enough data this month yet.")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-month-row-\(row.key)")
    }

    private func chipColor(_ row: PFMonthRow) -> Color {
        switch row.mark?.tone {
        case .good?: return NoopLook.trendUp
        case .bad?: return NoopLook.trendDown
        default: return NoopLook.textTertiary
        }
    }

    // MARK: Movers

    @ViewBuilder private func movers(_ period: PFMonthPeriod) -> some View {
        PFRuleLabel("WHAT MOVED")
        if period.movers.isEmpty {
            LookInfoCard(title: "Nothing moved by half a usual spread",
                         message: "A score or vital shows here when its month average moved by at least half its usual day-to-day spread.")
                .accessibilityIdentifier("pf-monthly-no-movers")
        } else {
            ForEach(period.movers) { mover in moverCard(mover) }
        }
    }

    private func moverCard(_ mover: PFMonthMover) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mover.label)
                    .font(LookFont.text(16, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                if let pct = mover.pct {
                    PFChip(text: PFImpactFormat.pctText(pct),
                           color: mover.assessment == "better" ? NoopLook.trendUp : (mover.assessment == "worse" ? NoopLook.trendDown : NoopLook.textTertiary))
                }
            }
            if let previous = mover.previous, let current = mover.current {
                let unit = (mover.unit?.isEmpty == false) ? " \(mover.unit ?? "")" : ""
                Text(shown(String(format: "%.1f", previous) + unit, key: mover.key) + "  \u{2192}  " + shown(String(format: "%.1f", current) + unit, key: mover.key))
                    .font(LookFont.numeral(18))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            if mover.whatMoved.isEmpty {
                Text("No behaviour lined up with this change.")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT MOVED IT").lookCaps(10.5).foregroundStyle(NoopLook.textTertiary)
                    ForEach(Array(mover.whatMoved.enumerated()), id: \.offset) { _, link in
                        Text("\u{2022} " + hiding.text(link.sentence))
                            .font(LookFont.text(14, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let action = mover.action {
                PFIntelActionCard(action: action, identifier: "pf-mover-action-\(mover.key)")
            }
            PFSourceTag(source: mover.source)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-mover-\(mover.key)")
    }

    // MARK: Goals and focus

    private func goalCard(_ goal: PFMonthGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(goal.title.uppercased()).lookCaps(11.5).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                if let status = goal.status {
                    PFChip(text: PFFormat.capitalized(status),
                           color: status == "behind" ? NoopLook.trendDown : (status == "on track" || status == "ahead" ? NoopLook.trendUp : NoopLook.textTertiary))
                }
            }
            if let headline = goal.headline {
                Text(hiding.text(headline))
                    .font(LookFont.text(17, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text = goal.text {
                Text(hiding.text(text))
                    .font(LookFont.text(14, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFSourceTag(source: goal.source)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-goal-\(goal.id)")
    }

    private func focusCard(_ focus: PFMonthFocus) -> some View {
        InsightCardFrame {
            Text(hiding.text(focus.text))
                .font(LookFont.text(15.5, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let why = focus.why {
                Text(hiding.text(why))
                    .font(LookFont.text(14, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let effort = focus.effortText {
                PFChip(text: PFFormat.capitalized(effort), color: effort == "no extra time" ? PFColor.positive : StrandPalette.accent)
            }
        }
        .containerIdentifier("pf-focus-\(focus.index)")
    }
}

#if DEBUG
#Preview("Monthly report") {
    NavigationStack {
        ScrollView {
            PFMonthlyReportBody(report: PFPhase4Sample.monthly, item: PFPhase4Sample.item(PFDocID.monthlyReport))
                .padding(16)
        }
        .lookScreenBackground()
    }
    .preferredColorScheme(.dark)
}
#endif
