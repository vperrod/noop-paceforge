#if os(iOS)
import SwiftUI
import StrandDesign
import UIKit

// NOOP Today's ONE row of six rings, the iPhone twin of the web Overview's two ring groups side by side: NOOP's Rest, Charge and
// Effort (from the WHOOP strap) on the left, PaceForge's Recovery, Sleep and Strain (from Garmin data) on the right. The two
// groups are two calculations and are never merged or averaged.
//
// Built small on purpose (builds 465 to 478): every part is its own small view with few children, there is no GeometryReader,
// ViewThatFits or preference key around the rings (the ring size is worked out ONCE, from the screen width), and PFBuilder is
// never called from here. The PaceForge numbers come from PFScoresStore (PaceForgeScoresGroup.swift): this file fetches nothing.

// MARK: - Layout

enum SixRingsLayout {
    /// The Today column's side padding on both edges (NoopMetrics.screenHPadding each).
    private static let columnPadding: CGFloat = NoopMetrics.screenHPadding * 2
    /// Room the thin divider between the groups takes: 6 + 1 + 6.
    static let dividerSlot: CGFloat = 13
    private static let minDiameter: CGFloat = 52
    private static let maxDiameter: CGFloat = 72
    /// What a ring does not use of its cell, so the name under it can be a little wider than the ring.
    private static let cellSlack: CGFloat = 2

    /// (screen width - column padding - divider) / 6, floored, less the slack. Once per launch: the row never measures itself.
    static let diameter: CGFloat = {
        let cell = ((UIScreen.main.bounds.width - columnPadding - dividerSlot) / 6).rounded(.down)
        return min(max(cell - cellSlack, minDiameter), maxDiameter)
    }()

    static var cellWidth: CGFloat { diameter + cellSlack }
    static var groupWidth: CGFloat { cellWidth * 3 }
    static var rowWidth: CGFloat { groupWidth * 2 + dividerSlot }

    /// Names under the rings: 10 pt, tracked 0.04em; RECOVERY is the longest word and gets 9.5.
    static func nameSize(_ name: String) -> CGFloat { name.count > 7 ? 9.5 : 10 }
}

// MARK: - The row

/// One NOOP ring's inputs, worked out by Today (which owns the scores, the scale and the Effort target).
struct SixRingNoopInput {
    let name: String
    /// On whatever scale the caller passes; nil = no data yet.
    let score: Double?
    let maxValue: Double
    let decimals: Int
    let tint: Color
    let unit: String?
    let target: (start: Double, end: Double)?
    /// Where the ring taps through to (the metric's trend and readings).
    let route: TabRoute?
    /// The name's tap: the scoring guide.
    let onGuide: () -> Void
}

/// The six rings and, under them, the never-merged note. `isToday` false (a past day): PaceForge's scores are today's only.
struct TodaySixRings: View {
    let noop: [SixRingNoopInput]
    let isToday: Bool

    private var noopCount: Int { noop.filter { $0.score != nil }.count }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                TodayNoopRingGroup(inputs: noop)
                SixRingsDivider()
                TodayPFRingGroup(noopCount: noopCount, isToday: isToday)
            }
            .frame(maxWidth: .infinity)
            TodaySixRingsFooter(noopCount: noopCount, isToday: isToday)
        }
        .containerIdentifier("today-six-rings")
    }
}

private struct SixRingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(NoopLook.track)
            .frame(width: 1, height: SixRingsLayout.diameter)
            .padding(.horizontal, 6)
            .padding(.top, 22)
            .accessibilityHidden(true)
    }
}

/// "NOOP  WHOOP strap" over the first three rings, "PACEFORGE  from Garmin data" over the last three.
private struct SixRingsGroupLabel: View {
    let chip: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(chip)
                .font(LookFont.text(9, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(color.opacity(0.16)))
            Text(text)
                .font(LookFont.text(10, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: SixRingsLayout.groupWidth)
    }
}

// MARK: - NOOP group

private struct TodayNoopRingGroup: View {
    let inputs: [SixRingNoopInput]

    var body: some View {
        VStack(spacing: 8) {
            SixRingsGroupLabel(chip: "NOOP", color: NoopLook.textSecondary, text: String(localized: "WHOOP strap"))
            HStack(spacing: 0) {
                ForEach(Array(inputs.enumerated()), id: \.offset) { _, input in
                    SixRingCell(spec: Self.spec(input), route: input.route, action: input.onGuide)
                }
            }
        }
    }

    private static func spec(_ input: SixRingNoopInput) -> SixRingSpec {
        let text = input.score.map { score in
            input.decimals > 0 ? String(format: "%.\(input.decimals)f", locale: AppLanguage.activeLocale, score)
                               : String(Safe.int(score))
        }
        return SixRingSpec(name: input.name, fraction: input.score.map { LookDial.fraction($0, max: input.maxValue) } ?? 0,
                           color: input.tint, valueText: text ?? "\u{2013}", unitText: input.score == nil ? nil : input.unit,
                           target: input.target, identifier: "six-rings-noop-\(input.name.lowercased())")
    }
}

// MARK: - PaceForge group

private struct TodayPFRingGroup: View {
    let noopCount: Int
    let isToday: Bool
    @ObservedObject private var store = PFScoresStore.shared
    /// A wearer who takes the watch off at night has no PaceForge Recovery or Sleep score: those two rings leave, Strain stays.
    @ObservedObject private var reports = PFReportsStore.shared
    @State private var isWhyOpen = false
    private let hiding = PFHiding()

    private var values: PFScoresValues? { isToday ? store.values : nil }

    private var pfCount: Int {
        guard let values else { return 0 }
        return (values.recovery != nil ? 1 : 0) + (values.sleep != nil ? 1 : 0) + (values.strain != nil ? 1 : 0)
    }

    private var crumbKey: Int { noopCount * 10 + pfCount }

    // A stack with its own .task: an empty view never runs it, and the load must start whether or not there is anything to draw.
    var body: some View {
        VStack(spacing: 8) {
            SixRingsGroupLabel(chip: "PaceForge", color: PFColor.sky, text: String(localized: "from Garmin data"))
            HStack(spacing: 0) {
                if reports.showsOvernight {
                    SixRingCell(spec: recovery, route: nil, action: openWhy)
                    SixRingCell(spec: sleep, route: nil, action: openWhy)
                }
                SixRingCell(spec: strain, route: nil, action: openWhy)
            }
        }
        .task { await store.refreshIfStale() }
        .onAppear { crumb() }
        .onChangeCompat(of: crumbKey) { _ in crumb() }
        .sheet(isPresented: $isWhyOpen) {
            if let values { PFExplainerSheet(explainer: values.sheetExplainer(hidingScores: hiding.hides(.scores))) }
        }
    }

    private func openWhy() {
        if values != nil { isWhyOpen = true }
    }

    private func crumb() {
        NoopDiag.crumb("today.rings6 noop=\(noopCount) pf=\(pfCount)")
    }

    private var recovery: SixRingSpec {
        let score = values?.recovery
        return SixRingSpec(name: String(localized: "Recovery"), fraction: score.map { LookDial.fraction($0, max: 100) } ?? 0,
                           color: score.map { NoopLook.chargeColor($0) } ?? NoopLook.chargeHigh,
                           valueText: score.map { String(Safe.int($0)) } ?? "\u{2013}", unitText: score == nil ? nil : "%",
                           target: nil, identifier: "six-rings-pf-recovery")
    }

    private var sleep: SixRingSpec {
        let score = values?.sleep
        return SixRingSpec(name: String(localized: "Sleep"), fraction: score.map { LookDial.fraction($0, max: 100) } ?? 0,
                           color: NoopLook.rest, valueText: score.map { String(Safe.int($0)) } ?? "\u{2013}",
                           unitText: score == nil ? nil : "%", target: nil, identifier: "six-rings-pf-sleep")
    }

    private var strain: SixRingSpec {
        let score = values?.strain
        let target = score == nil ? nil : LookDial.targetArc(low: values?.strainLow, high: values?.strainHigh, max: 21)
        return SixRingSpec(name: String(localized: "Strain"), fraction: score.map { LookDial.fraction($0, max: 21) } ?? 0,
                           color: NoopLook.effort, valueText: score.map { PFFormat.oneDecimal($0) } ?? "\u{2013}",
                           unitText: nil, target: target, identifier: "six-rings-pf-strain")
    }
}

extension PFScoresValues {
    /// The sheet behind a PaceForge ring: the day's readings that do not fit under the rings (the sleep line, Garmin's own sleep
    /// score, the Strain target), then the "why the scores differ" explainer. Under Hide numbers only the explainer.
    func sheetExplainer(hidingScores: Bool) -> PFExplainer {
        guard !hidingScores else { return why }
        var lines: [String] = []
        if let recovery { lines.append("Recovery \(Safe.int(recovery))%") }
        if let sleep { lines.append("Sleep \(Safe.int(sleep))%" + (sleepLine.map { " (\($0))" } ?? "")) }
        if let garminSleep { lines.append("Garmin's own sleep score \(Safe.int(garminSleep))") }
        if let strain {
            var line = "Strain \(PFFormat.oneDecimal(strain)) of 21"
            if let low = strainLow, let high = strainHigh {
                line += ", target \(Safe.int(low, .towardZero))\u{2013}\(Safe.int(high, .towardZero))"
            }
            lines.append(line)
        }
        guard !lines.isEmpty else { return why }
        var out = why
        out.plain = lines.joined(separator: "\n") + (why.plain.map { "\n\n" + $0 } ?? "")
        return out
    }
}

// MARK: - One ring

struct SixRingSpec {
    let name: String
    let fraction: Double
    let color: Color
    let valueText: String
    let unitText: String?
    let target: (start: Double, end: Double)?
    let identifier: String
}

/// One cell: the compact RingDial and its name under it. The ring taps through to `route` when there is one, else runs `action`;
/// the name always runs `action`. Under Hide numbers the ring reads two dots and stays empty, like the other Today dials.
private struct SixRingCell: View {
    let spec: SixRingSpec
    let route: TabRoute?
    let action: () -> Void
    private let hiding = PFHiding()

    private var isHidden: Bool { hiding.hides(.scores) }

    private var spoken: String {
        if isHidden { return "\(spec.name), hidden" }
        return "\(spec.name), \(spec.valueText)\(spec.unitText ?? "")"
    }

    var body: some View {
        VStack(spacing: 6) {
            ring
            name
        }
        .frame(width: SixRingsLayout.cellWidth)
        .containerIdentifier(spec.identifier)
    }

    private var dial: some View {
        RingDial(fraction: isHidden ? 0 : spec.fraction, color: spec.color, valueText: isHidden ? "\u{2022}\u{2022}" : spec.valueText,
                 unitText: isHidden ? nil : spec.unitText, target: isHidden ? nil : spec.target,
                 diameter: SixRingsLayout.diameter, accessibilityName: spec.name)
    }

    @ViewBuilder private var ring: some View {
        if let route {
            NavigationLink(value: route) { dial.contentShape(Rectangle()) }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel(Text(spoken))
                .accessibilityHint(Text("Opens the trend and readings"))
        } else {
            Button(action: action) { dial.contentShape(Rectangle()) }
                .buttonStyle(LiquidPressStyle())
                .accessibilityLabel(Text(spoken))
                .accessibilityHint(Text("Shows how the scores differ"))
        }
    }

    private var name: some View {
        let size = SixRingsLayout.nameSize(spec.name)
        return Button(action: action) {
            Text(spec.name)
                .font(LookFont.text(size, weight: .semibold))
                .tracking(size * 0.04)
                .textCase(.uppercase)
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: SixRingsLayout.cellWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(spoken))
    }
}

// MARK: - Footer

/// Under the row: the never-merged note with its About link, and one line saying why when a group has nothing to show.
private struct TodaySixRingsFooter: View {
    let noopCount: Int
    let isToday: Bool
    @ObservedObject private var store = PFScoresStore.shared
    @State private var isAboutOpen = false

    private static let note: AttributedString = {
        let text = "NOOP and PaceForge are two different calculations, never merged. [About these scores](noop-about://scores)"
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }()

    /// Why the PaceForge half is empty, or nil while it has at least one score.
    private var pfReason: String? {
        guard isToday else { return "PaceForge scores show for today only." }
        guard let values = store.values else { return nil }
        return values.hasAny ? nil : values.reason
    }

    private var reasons: [String] {
        var out: [String] = []
        if noopCount == 0 { out.append("NOOP has no scores for this day yet.") }
        if let pfReason { out.append(pfReason) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.note)
                .font(LookFont.text(11, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .tint(PFColor.sky)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("six-rings-note")
            ForEach(reasons, id: \.self) { reason in
                Text(reason)
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("six-rings-reason")
            }
            if isAboutOpen {
                Text("Rest, Charge and Effort come from the strap. Recovery and Sleep are PaceForge's own calculation from Garmin's HRV, resting heart rate and sleep, and Strain runs 0 to 21. Garmin's own training readiness is a different number again.")
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("six-rings-about-text")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "noop-about" else { return .systemAction }
            isAboutOpen.toggle()
            return .handled
        })
    }
}
#endif
