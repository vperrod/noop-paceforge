import SwiftUI
import StrandDesign

// The Coach screen's three server-built panels: "Your numbers", the readiness panel (also on Today) and the season plan. Read-only;
// the parsing and the wording are in PaceForgeCoachNumbers.swift. A panel draws nothing until the server serves its document.

@MainActor
final class PFCoachPanelsStore: ObservableObject {
    static let shared = PFCoachPanelsStore()

    static let numbersPath = "api/athlete-numbers"
    static let readinessPath = "api/readiness-decision"
    static let seasonPath = "api/season-plan"

    @Published private(set) var numbers: PFAthleteNumbers?
    @Published private(set) var readiness: PFDeviceReadiness?
    @Published private(set) var season: PFSeasonPlan?

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 60 { return }
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
        async let numbersDoc = PFAPI.fetchDoc(Self.numbersPath)
        async let readinessDoc = PFAPI.fetchDoc(Self.readinessPath)
        async let seasonDoc = PFAPI.fetchDoc(Self.seasonPath)
        let (n, r, s) = await (numbersDoc, readinessDoc, seasonDoc)
        // A document the server could not be asked for keeps what is on screen; one it does not serve (404) clears its panel.
        if !n.failed {
            let parsed = PFCoachNumbers.athleteNumbers(n.data)
            if numbers != parsed { numbers = parsed }
        }
        if !r.failed {
            let parsed = PFDeviceReadinessParse.readiness(r.data)
            if readiness != parsed { readiness = parsed }
        }
        if !s.failed {
            let parsed = PFSeasonParse.plan(s.data)
            if season != parsed { season = parsed }
        }
        if !(n.failed && r.failed && s.failed) { lastFetch = Date() }
    }
}

// MARK: Your numbers

struct PFNumbersCard: View {
    @ObservedObject private var store = PFCoachPanelsStore.shared
    private let hiding = PFHiding()

    var body: some View {
        if let numbers = store.numbers {
            PFCard("Your numbers", icon: "gauge.with.dots.needle.50percent") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(numbers.rows) { row in
                        figureRow(label: row.label, value: row.value, caption: row.caption)
                    }
                    if !numbers.paces.isEmpty {
                        Text("Pace bands")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .padding(.top, 4)
                        ForEach(numbers.paces) { band in
                            figureRow(label: band.label, value: band.range ?? "\u{2013}", caption: band.caption)
                        }
                    }
                }
            }
            .accessibilityIdentifier("coach-your-numbers")
        }
    }

    private func figureRow(label: String, value: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text(caption).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 8)
            Text(hiding.text(value))
                .font(LookFont.numeral(18))
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Readiness

/// Garmin and WHOOP side by side, each with its own values and status, then the coach's decision. No combined number is drawn.
struct PFDualReadinessPanel: View {
    @ObservedObject private var store = PFCoachPanelsStore.shared
    private let hiding = PFHiding()

    var body: some View {
        if let readiness = store.readiness {
            PFCard("Readiness", icon: "heart.text.square") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        column("Garmin", readiness.garmin)
                        column("WHOOP", readiness.whoop)
                    }
                    if let decision = readiness.decision { decisionBlock(decision, agreement: readiness.agreement) }
                    else if let agreement = readiness.agreement { agreementMark(agreement) }
                }
            }
            .accessibilityIdentifier("readiness-panel")
        }
    }

    private func column(_ title: String, _ device: PFDeviceBlock?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                if let status = device?.status { PFChip(text: status, color: Self.color(PFStatusTone.of(status))) }
            }
            if let device {
                ForEach(device.metrics) { metricRow($0) }
                if !device.load.isEmpty {
                    Text("Load").font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textTertiary)
                    ForEach(device.load) { metricRow($0) }
                }
                if let method = device.method {
                    Text("Method: " + method).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No reading").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readiness-" + title.lowercased())
    }

    private func metricRow(_ metric: PFDeviceMetric) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(metric.name).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let value = metric.value {
                    Text(hiding.text(value))
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let unit = metric.unit { Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
                }
                if let status = metric.status {
                    Text(status).font(StrandFont.caption.weight(.semibold)).foregroundStyle(Self.color(metric.tone))
                }
            }
            if let baseline = metric.baseline {
                Text("baseline " + hiding.text(baseline)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            if metric.isNotUsedForDecisions {
                Text(PFDeviceMetric.notUsedNote).font(StrandFont.caption.italic()).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func decisionBlock(_ decision: PFReadinessCall, agreement: PFDeviceAgreement?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hiding.text(decision.sentence))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let rule = decision.ruleLine {
                Text(rule).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let agreement { agreementMark(agreement) }
            if let question = decision.question {
                Text(question).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let guardText = decision.raceGuard {
                Text("Race guard: " + guardText).font(StrandFont.caption).foregroundStyle(PFColor.warning)
            }
        }
        .padding(.top, 4)
        .accessibilityIdentifier("readiness-decision")
    }

    private func agreementMark(_ agreement: PFDeviceAgreement) -> some View {
        let agrees = agreement == .agree
        return HStack(spacing: 6) {
            Image(systemName: agrees ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(agrees ? "Garmin and WHOOP agree" : "Garmin and WHOOP split")
                .font(StrandFont.caption.weight(.semibold))
        }
        .foregroundStyle(agrees ? PFColor.positive : PFColor.warning)
    }

    private static func color(_ tone: PFStatusTone) -> Color {
        switch tone {
        case .good: return PFColor.positive
        case .caution: return PFColor.warning
        case .bad: return PFColor.critical
        case .unknown: return StrandPalette.textSecondary
        }
    }
}

/// The panel with its own load, for Today (the Coach screen loads the store with its other cards).
struct PFDualReadinessHost: View {
    var body: some View {
        PFDualReadinessPanel()
            .task { await PFCoachPanelsStore.shared.refreshIfStale() }
    }
}

// MARK: Season plan

struct PFSeasonPlanCard: View {
    @ObservedObject private var store = PFCoachPanelsStore.shared

    var body: some View {
        if let plan = store.season {
            let today = PFAPI.todayISO
            PFCard("Season plan", icon: "calendar.day.timeline.left") {
                VStack(alignment: .leading, spacing: 12) {
                    if let current = plan.current(today: today) { currentBlock(current) }
                    ForEach(PFSeasonParse.timeline(plan, today: today)) { item in row(item) }
                    if !plan.weekRules.isEmpty {
                        Text("Week rules")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .padding(.top, 4)
                        ForEach(Array(plan.weekRules.enumerated()), id: \.offset) { _, rule in
                            Text("\u{2022} " + rule)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .accessibilityIdentifier("coach-season-plan")
        }
    }

    private func currentBlock(_ block: PFSeasonBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Now: \(block.title) block, \(block.span)")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
            if let aim = block.aim {
                Text("Aim: " + aim).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func row(_ item: PFSeasonItem) -> some View {
        switch item {
        case .race(let race):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PFColor.critical)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(race.name).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PFFormat.dayTitle(race.date) + (race.priorityLabel.map { " \u{00B7} " + $0 } ?? ""))
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    if race.assumed {
                        Text(PFSeasonRace.assumedNote).font(StrandFont.caption.weight(.semibold)).foregroundStyle(PFColor.warning)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        case .block(let block, let isCurrent):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.color(block.kind))
                    .frame(width: 4, height: 32)
                    .padding(.horizontal, 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(block.title).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                        if isCurrent { PFChip(text: "now", color: StrandPalette.accent) }
                    }
                    Text(block.span + (block.race.map { " \u{00B7} toward " + $0 } ?? ""))
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private static func color(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "base": return PFColor.sky
        case "build": return PFColor.warning
        case "peak", "race": return PFColor.critical
        case "taper": return PFColor.violet
        case "recovery", "rest", "transition": return PFColor.positive
        default: return StrandPalette.textTertiary
        }
    }
}
