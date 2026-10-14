import SwiftUI
import StrandDesign

// The daily loop on screen (plan "UI matching", Part B): Today's call, the Health monitor tile and screen, What moved it
// and Day in review. Every card is the look's: a 12 pt tile or the gradient-bordered insight frame, caps labels and
// the numeral face. They read daily-intel.json through `PFDailyIntelStore`, say whose score each number is (NOOP's strap,
// PaceForge's Garmin) and never merge the two, and show the server's own reason when an item is unavailable.

// MARK: - Small shared pieces

/// A quiet card for a state with nothing to chart: not worked out yet, or unavailable with the server's reason.
struct PFIntelNote: View {
    let title: String
    let icon: String
    let text: String
    let identifier: String

    var body: some View {
        PFCard(title, icon: icon) {
            PFParagraph(text)
        }
        .containerIdentifier(identifier)
    }
}

/// One suggested action in the insight-card frame. The link opens the reason and the time it costs in place.
struct PFIntelActionCard: View {
    let action: PFInsightAction
    let identifier: String
    @State private var isOpen = false
    private let hiding = PFHiding()

    var body: some View {
        InsightCardFrame {
            Text(hiding.text(action.text))
                .font(LookFont.text(15.5, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if isOpen {
                if let why = action.why {
                    Text(hiding.text(why))
                        .font(LookFont.text(14.5, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if let effort = action.effort {
                        PFChip(text: effort.chipText, color: effort.isFree ? PFColor.positive : StrandPalette.accent)
                    }
                    if let impact = action.impactText {
                        PFChip(text: impact, color: StrandPalette.textTertiary)
                    }
                    Spacer(minLength: 4)
                }
            }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                InsightLink(isOpen ? "Hide the reason" : "Why, and what it costs")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(identifier)-link")
        }
        .containerIdentifier(identifier)
    }
}

/// "Sources: NOOP · PaceForge. High confidence." and the server's data note, under a card.
struct PFIntelFootnote: View {
    let item: PFIntelItem
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let sources = item.sourceText
            let confidence = item.base.confidenceText ?? ""
            let line = [sources.isEmpty ? "" : "Sources: \(sources)", confidence].filter { !$0.isEmpty }.joined(separator: ". ")
            if !line.isEmpty {
                Text(line)
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            if let note = item.base.dataNote {
                Text(hiding.text(note))
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled line: a caps label over one sentence, with a symbol. Used for the planned session and tomorrow.
private struct PFIntelLine: View {
    let label: String
    let text: String
    let icon: String
    private let hiding = PFHiding()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .lookCaps(10.5)
                    .foregroundStyle(NoopLook.textTertiary)
                Text(hiding.text(text))
                    .font(LookFont.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today's call

/// One dial of the card: the ring, whose score it is, and a line under it.
private struct PFCallDial: View {
    let fraction: Double
    let color: Color
    let valueText: String
    var unitText: String?
    var target: (start: Double, end: Double)?
    let caption: String
    var sub: String?
    let name: String
    let identifier: String

    var body: some View {
        VStack(spacing: 6) {
            RingDial(fraction: fraction, color: color, valueText: valueText, unitText: unitText, target: target,
                     diameter: 84, accessibilityName: name)
            Text(caption)
                .lookCaps(10)
                .foregroundStyle(NoopLook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let sub {
                Text(sub)
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .containerIdentifier(identifier)
    }
}

/// TODAY'S CALL: the verdict chip, NOOP's Charge and PaceForge's readiness side by side, the Effort target, the planned
/// session, the sentence on why the two scores differ when they do, and the actions.
struct PFTodaysCallCard: View {
    let call: PFTodaysCall
    let item: PFIntelItem
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 4) {
                chargeDial
                readinessDial
                effortDial
            }
            if let progress = call.effortTarget?.progress?.text {
                Text(hiding.text(progress))
                    .font(LookFont.text(13.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pf-call-effort-progress")
            }
            if let sentence = item.base.meaning ?? call.verdict {
                Text(hiding.text(sentence))
                    .font(LookFont.text(15.5, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-call-verdict-text")
            }
            if let disagreement = call.disagreement {
                PFIntelLine(label: "Why the two scores differ", text: disagreement.text, icon: "arrow.triangle.branch")
                    .accessibilityIdentifier("pf-call-disagreement")
            }
            sessions
            ForEach(item.base.actions) { action in
                PFIntelActionCard(action: action, identifier: "pf-call-action-\(action.id)")
            }
            PFIntelFootnote(item: item)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-todays-call")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .accessibilityHidden(true)
            Text("Today's call")
                .lookCaps(12.5)
                .foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 8)
            PFChip(text: call.call.chipText, color: PFInsightColor.color(for: call.call.tone))
                .accessibilityLabel(call.call.spokenText)
                .accessibilityIdentifier("pf-call-chip")
        }
    }

    // NOOP's Charge. The dial is labelled with whose score it is; a missing score is a dash, not a guess.
    @ViewBuilder private var chargeDial: some View {
        if let charge = call.charge {
            PFCallDial(fraction: hiding.hides(.scores) ? 0 : charge.score / 100,
                       color: hiding.hides(.scores) ? NoopLook.textTertiary : NoopLook.chargeColor(charge.score),
                       valueText: hiding.shown(String(charge.rounded), .scores), unitText: hiding.hides(.scores) ? nil : "%",
                       caption: "NOOP \u{00B7} Charge",
                       sub: charge.carriedFrom.map { "from \(PFFormat.shortDate($0))" },
                       name: "NOOP Charge", identifier: "pf-call-charge")
        } else {
            PFCallDial(fraction: 0, color: NoopLook.textTertiary, valueText: "\u{2013}", caption: "NOOP \u{00B7} Charge",
                       sub: "not scored yet", name: "NOOP Charge", identifier: "pf-call-charge")
        }
    }

    // PaceForge's readiness, from the Garmin watch. Side by side with Charge, never averaged with it.
    @ViewBuilder private var readinessDial: some View {
        if let readiness = call.readiness {
            PFCallDial(fraction: hiding.hides(.scores) ? 0 : readiness.score / 100,
                       color: hiding.hides(.scores) ? NoopLook.textTertiary : NoopLook.chargeColor(readiness.score),
                       valueText: hiding.shown(String(readiness.rounded), .scores), unitText: hiding.hides(.scores) ? nil : "%",
                       caption: "PaceForge \u{00B7} Readiness", name: "PaceForge readiness", identifier: "pf-call-readiness")
        } else {
            PFCallDial(fraction: 0, color: NoopLook.textTertiary, valueText: "\u{2013}",
                       caption: "PaceForge \u{00B7} Readiness", sub: "not scored yet", name: "PaceForge readiness",
                       identifier: "pf-call-readiness")
        }
    }

    // Effort so far, with the target arc and its tick drawn on the dial.
    @ViewBuilder private var effortDial: some View {
        if let target = call.effortTarget {
            let hidden = hiding.hides(.scores)
            PFCallDial(fraction: hidden ? 0 : (target.effortFraction ?? 0), color: NoopLook.effort,
                       valueText: hiding.shown(target.effortNow.map { String(Int($0.rounded())) } ?? "\u{2013}", .scores),
                       target: target.arc, caption: "Effort target \(hiding.shown(target.rangeText, .scores))",
                       sub: target.effortSource, name: "Effort", identifier: "pf-call-effort")
        } else {
            PFCallDial(fraction: 0, color: NoopLook.textTertiary, valueText: "\u{2013}", caption: "Effort target",
                       sub: "needs a Charge first", name: "Effort target", identifier: "pf-call-effort")
        }
    }

    @ViewBuilder private var sessions: some View {
        if let session = call.plannedSession {
            PFIntelLine(label: "Planned today", text: session.lineText, icon: "figure.run")
                .accessibilityIdentifier("pf-call-session")
        } else {
            PFIntelLine(label: "Planned today", text: "No session planned", icon: "figure.run")
                .accessibilityIdentifier("pf-call-session")
        }
        if let tomorrow = call.tomorrowSession {
            PFIntelLine(label: "Tomorrow", text: tomorrow.lineText, icon: "calendar")
                .accessibilityIdentifier("pf-call-tomorrow")
        }
    }
}

/// Today's call for a given document: the card, "not worked out yet" for a file from another day, or the server's
/// reason when the item is unavailable. Nothing when the server sent no such item.
struct PFTodaysCallHost: View {
    let intel: PFDailyIntel?
    let todayISO: String

    var body: some View {
        if let intel {
            content(intel)
        }
    }

    @ViewBuilder private func content(_ intel: PFDailyIntel) -> some View {
        if intel.item(PFIntelID.todaysCall) == nil {
            EmptyView()
        } else if !intel.isCurrent(for: todayISO) {
            let when = intel.asOf.map { PFFormat.shortDate($0) } ?? "an earlier day"
            PFIntelNote(title: "Today's call", icon: "scope",
                        text: "Today's call has not been worked out yet. The last one is from \(when).",
                        identifier: "pf-todays-call-stale")
        } else if let call = intel.call, let item = intel.callItem {
            PFTodaysCallCard(call: call, item: item)
        } else {
            PFIntelNote(title: "Today's call", icon: "scope",
                        text: intel.unavailableReason(PFIntelID.todaysCall) ?? "Today's call is not available yet.",
                        identifier: "pf-todays-call-unavailable")
        }
    }
}

/// NOOP Today's Today's call: reads the shared store and refreshes it when its copy is old.
struct PFTodaysCallStoreHost: View {
    @ObservedObject private var store = PFDailyIntelStore.shared

    var body: some View {
        PFTodaysCallHost(intel: store.intel, todayISO: PFAPI.todayISO)
            .task { await store.refreshIfStale() }
    }
}

// MARK: - Day in review

/// The evening wrap: did Effort reach its range, tonight's need and bedtime, tomorrow's session.
struct PFDayReviewCard: View {
    let review: PFDayReview
    let item: PFIntelItem
    private let hiding = PFHiding()

    private var outcomeColor: Color {
        switch review.outcome {
        case .met: return PFColor.positive
        case .notMet: return PFColor.warning
        case .noTarget: return StrandPalette.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
                Text("Day in review")
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                PFChip(text: review.outcomeText, color: outcomeColor)
                    .accessibilityIdentifier("pf-review-outcome")
            }
            if let effort = review.effortText {
                PFIntelLine(label: "Effort against its range", text: hiding.shown(effort, .scores), icon: "gauge.with.dots.needle.67percent")
                    .accessibilityIdentifier("pf-review-effort")
            }
            if let tonight = review.tonight {
                PFIntelLine(label: "Tonight", text: tonightText(tonight), icon: "bed.double")
                    .accessibilityIdentifier("pf-review-tonight")
            }
            if let tomorrow = review.tomorrow {
                PFIntelLine(label: "Tomorrow", text: tomorrow.lineText, icon: "calendar")
                    .accessibilityIdentifier("pf-review-tomorrow")
            }
            if let sentence = review.sentence {
                Text(hiding.text(sentence))
                    .font(LookFont.text(15, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-review-sentence")
            }
            ForEach(item.base.actions) { action in
                PFIntelActionCard(action: action, identifier: "pf-review-action-\(action.id)")
            }
            PFIntelFootnote(item: item)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-day-review")
    }

    private func tonightText(_ tonight: PFTonight) -> String {
        var parts: [String] = []
        if let bedtime = tonight.bedtime { parts.append("In bed by \(bedtime)") }
        if let need = tonight.needText { parts.append("needs \(need) of sleep") }
        if let tier = tonight.tier { parts.append("\(tier) goal") }
        return parts.isEmpty ? "No sleep need yet" : parts.joined(separator: ", ")
    }
}

/// Day in review, evening only: after 18:00 local. Before that nothing shows.
struct PFDayReviewHost: View {
    let intel: PFDailyIntel?
    let todayISO: String

    var body: some View {
        if let intel, PFIntelClock.isEvening(), intel.isCurrent(for: todayISO), intel.item(PFIntelID.dayInReview) != nil {
            if let review = intel.review, let item = intel.reviewItem {
                PFDayReviewCard(review: review, item: item)
            } else {
                PFIntelNote(title: "Day in review", icon: "moon.stars",
                            text: intel.unavailableReason(PFIntelID.dayInReview) ?? "The day's review is not available yet.",
                            identifier: "pf-day-review-unavailable")
            }
        }
    }
}

struct PFDayReviewStoreHost: View {
    @ObservedObject private var store = PFDailyIntelStore.shared

    var body: some View {
        PFDayReviewHost(intel: store.intel, todayISO: PFAPI.todayISO)
            .task { await store.refreshIfStale() }
    }
}

// MARK: - Health monitor

enum PFHealthStyle {
    /// Within range is the good end, an out-of-range vital is amber, "very" far out is red.
    static func color(for vital: PFVital) -> Color {
        if !vital.isOut { return NoopLook.trendUp }
        return vital.isVeryOut ? NoopLook.alert : NoopLook.trendDown
    }

    static func color(for tile: PFHealthTile) -> Color {
        if tile.isRed { return NoopLook.alert }
        return tile.state == .withinRange ? NoopLook.trendUp : NoopLook.trendDown
    }
}

/// The Health monitor tile on NOOP Today: "WITHIN RANGE · 4/4 metrics", or "VERY ELEVATED · Respiratory rate" in red.
struct PFHealthMonitorTile: View {
    let tile: PFHealthTile

    var body: some View {
        let color = PFHealthStyle.color(for: tile)
        MonitorTile(title: String(localized: "Health monitor"),
                    badge: .symbol(tile.state == .withinRange ? "checkmark" : "exclamationmark"),
                    badgeForeground: color, badgeBackground: tile.isRed ? NoopLook.alertWash : color.opacity(0.16),
                    status: tile.status, statusColor: color, detail: tile.detail)
    }
}

/// A bar with the 30-day typical band drawn on it and a marker where today's value sits.
struct PFRangeBandBar: View {
    let band: PFRangeBand
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NoopLook.track)
                    .frame(height: 6)
                Capsule()
                    .fill(NoopLook.sufficient.opacity(0.55))
                    .frame(width: max((band.high - band.low) * width, 4), height: 6)
                    .offset(x: band.low * width)
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(NoopLook.card, lineWidth: 2))
                    .offset(x: min(max(band.marker * width - 7, 0), max(width - 14, 0)))
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

/// One vital: its value, the 30-day typical band with an in/out marker, the word, and whose reading it is.
struct PFVitalRow: View {
    let vital: PFVital

    var body: some View {
        let color = PFHealthStyle.color(for: vital)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(vital.label)
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let value = vital.valueText {
                    Text(value)
                        .font(LookFont.numeral(25))
                        .foregroundStyle(NoopLook.textPrimary)
                    if !vital.unitText.isEmpty {
                        Text(vital.unitText)
                            .font(LookFont.numeralRegular(13))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
            }
            if vital.available {
                if let band = vital.band {
                    PFRangeBandBar(band: band, color: color)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(vital.word ?? "")
                        .font(LookFont.text(13, weight: .bold))
                        .tracking(13 * 0.07)
                        .foregroundStyle(color)
                    if let range = vital.rangeText {
                        Text("Typical \(range)")
                            .font(LookFont.text(12.5, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                    Spacer(minLength: 4)
                    Text(vital.sourceLabel)
                        .lookCaps(10)
                        .foregroundStyle(NoopLook.textSecondary)
                }
            } else {
                Text(vital.reason ?? "Not enough readings yet")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(vital.sourceLabel)
                    .lookCaps(10)
                    .foregroundStyle(NoopLook.textSecondary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-vital-\(vital.key)")
    }
}

/// The Health monitor screen: the summary, each vital against its 30-day range, and the alert with what to do.
struct PFHealthMonitorScreen: View {
    @ObservedObject private var store = PFDailyIntelStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .lookScreenBackground()
        .navigationTitle("Health monitor")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pf-health-monitor")
        .task { await store.refreshIfStale() }
    }

    @ViewBuilder private var content: some View {
        if let intel = store.intel, let health = intel.health, let item = intel.healthItem {
            PFHealthMonitorBody(health: health, item: item, isCurrent: intel.isCurrent(for: PFAPI.todayISO), asOf: intel.asOf)
        } else if let reason = store.intel?.unavailableReason(PFIntelID.healthMonitor) {
            PFIntelNote(title: "Health monitor", icon: "waveform.path.ecg", text: reason, identifier: "pf-health-monitor-unavailable")
        } else if store.didLoad {
            PFIntelNote(title: "Health monitor", icon: "waveform.path.ecg",
                        text: "The Health monitor needs PaceForge. It is not reachable or has not published the vitals yet.",
                        identifier: "pf-health-monitor-empty")
        } else {
            Text("Reading your vitals")
                .font(LookFont.text(15, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
        }
    }
}

struct PFHealthMonitorBody: View {
    let health: PFHealthMonitor
    let item: PFIntelItem
    let isCurrent: Bool
    let asOf: String?
    private let hiding = PFHiding()

    var body: some View {
        let tile = health.tile
        VStack(alignment: .leading, spacing: 14) {
            summary(tile)
            if !isCurrent, let asOf {
                PFChip(text: "From \(PFFormat.shortDate(asOf))", color: StrandPalette.textTertiary)
            }
            explanation
            VStack(spacing: 0) {
                ForEach(Array(health.vitals.enumerated()), id: \.element.id) { index, vital in
                    PFVitalRow(vital: vital)
                    if index < health.vitals.count - 1 {
                        Rectangle().fill(NoopLook.divider).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .accessibilityIdentifier("pf-vitals")
            ForEach(item.base.actions) { action in
                PFIntelActionCard(action: action, identifier: "pf-health-action-\(action.id)")
            }
            PFIntelFootnote(item: item)
            Text("Each vital against the median of your own previous \(health.windowDays ?? 30) days, plus or minus one usual spread. Inside is within range; beyond one spread is elevated or low, beyond two is very.")
                .font(LookFont.text(12.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summary(_ tile: PFHealthTile) -> some View {
        let color = PFHealthStyle.color(for: tile)
        return HStack(spacing: 12) {
            Image(systemName: tile.state == .withinRange ? "checkmark" : "exclamationmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tile.isRed ? NoopLook.alertWash : color.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.status)
                    .font(LookFont.text(18, weight: .bold))
                    .tracking(18 * 0.07)
                    .foregroundStyle(color)
                Text(tile.detail)
                    .font(LookFont.text(14.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.tile))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-health-summary")
    }

    // The alert's explanation, or what the server says about the vitals, in the insight card.
    @ViewBuilder private var explanation: some View {
        if let alert = health.alert {
            InsightCardFrame {
                Text(alert.title)
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                if let explanation = alert.body {
                    Text(hiding.text(explanation))
                        .font(LookFont.text(15.5, weight: .medium))
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !alert.whatToDo.isEmpty {
                    Text("What to do")
                        .lookCaps(10.5)
                        .foregroundStyle(NoopLook.textTertiary)
                    ForEach(Array(alert.whatToDo.enumerated()), id: \.offset) { _, step in
                        Text("\u{2022} \(step)")
                            .font(LookFont.text(14.5, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .containerIdentifier("pf-health-alert")
        } else if let meaning = item.base.meaning {
            InsightCard(hiding.text(meaning))
                .accessibilityIdentifier("pf-health-meaning")
        }
    }
}

// MARK: - What moved it

/// "What moved it" for one metric: the change, what lined up with it and one action, in the insight frame. Shows nothing
/// when the server has no entry for the metric.
struct PFWhatMovedCard: View {
    let metric: PFMovedMetric
    let asOf: String?
    let isCurrent: Bool
    private let hiding = PFHiding()

    var body: some View {
        InsightCardFrame {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.up.right.and.arrow.down.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
                Text("What moved it")
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                PFChip(text: metric.chipText, color: chipColor)
            }
            Text(hiding.text(metric.headline))
                .font(LookFont.text(15.5, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pf-moved-headline")
            if metric.hasData {
                changeLines
                links
                if let action = metric.action {
                    Text("What to do")
                        .lookCaps(10.5)
                        .foregroundStyle(NoopLook.textTertiary)
                    Text(hiding.text(action.text))
                        .font(LookFont.text(14.5, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-moved-action")
                }
            }
            Text(footnote)
                .font(LookFont.text(12.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .containerIdentifier("pf-what-moved")
    }

    private var chipColor: Color {
        guard metric.hasData, metric.moved else { return StrandPalette.textTertiary }
        switch metric.assessment {
        case "better": return PFColor.positive
        case "worse": return PFColor.warning
        default: return StrandPalette.accent
        }
    }

    @ViewBuilder private var changeLines: some View {
        ForEach([metric.change7, metric.change30].compactMap { $0 }, id: \.days) { change in
            if let current = change.current, let previous = change.previous {
                Text("Last \(change.days) days \(PFNumber.trimmed(current)), the \(change.days) before \(PFNumber.trimmed(previous))")
                    .font(LookFont.text(13.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
            }
        }
    }

    @ViewBuilder private var links: some View {
        if metric.links.isEmpty {
            Text("Nothing in your logged days lines up with this change yet.")
                .font(LookFont.text(13.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Lined up with")
                .lookCaps(10.5)
                .foregroundStyle(NoopLook.textTertiary)
            ForEach(Array(metric.links.enumerated()), id: \.offset) { _, link in
                Text("\u{2022} \(link.sentence)")
                    .font(LookFont.text(14.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: String {
        var text = "Based on \(sourceWord) data. What lined up is a pattern, not proof of the cause."
        if !isCurrent, let asOf { text += " As of \(PFFormat.shortDate(asOf))." }
        return text
    }

    private var sourceWord: String {
        switch metric.source {
        case "NOOP"?: return "NOOP strap"
        case let other?: return other
        case nil: return "PaceForge"
        }
    }
}

/// The "What moved it" section for a screen's metric. `metricID` is a trend metric id or catalog key; `intelKey` names
/// the server's metric directly (hrv, resting_hr, sleep_hours, charge, effort, weight).
struct PFWhatMovedSection: View {
    private let key: String?
    @ObservedObject private var store = PFDailyIntelStore.shared

    init(metricID: String) { key = PFMovedMetricMap.intelKey(forMetricID: metricID) }
    init(intelKey: String) { key = intelKey }

    var body: some View {
        Group {
            if let key, let intel = store.intel, let metric = intel.moved?.metric(key) {
                PFWhatMovedCard(metric: metric, asOf: intel.asOf, isCurrent: intel.isCurrent(for: PFAPI.todayISO))
            }
        }
        .task { await store.refreshIfStale() }
    }
}

// MARK: - Previews

#if DEBUG
enum PFIntelSample {
    /// Made-up numbers, one of everything. Dates are the UI-test fixture's day.
    static let json = """
    {"version":1,"generated_at":"2030-03-13T19:05:00+00:00","as_of":"2030-03-13",
     "order":["todays_call","sleep_need_tonight","health_monitor","what_moved_it","day_in_review"],
     "items":{
      "todays_call":{"id":"todays_call","title":"Today's call","available":true,
       "metric":{"as_of":"2030-03-13",
        "charge":{"score":72,"band":"green","source":"NOOP","label":"Charge","carried_from":null},
        "readiness":{"score":41,"band":"yellow","source":"PaceForge","label":"Readiness","reason":"Synthetic reason"},
        "agreement":"mixed","disagreement":{"input":"hrv","text":"Your strap reads HRV above its usual while your watch reads it below, so the two scores differ."},
        "effort_target":{"low":52,"high":71,"charge_band":"green","scale":"0-100","basis":"NOOP Effort target rule on Charge",
         "progress":{"status":"to_go","effort":30,"low":52,"high":71,"to_go_low":22,"to_go_high":41,"above_by":0,"text":"Effort 30 of 52\\u201371: 22\\u201341 to go"},
         "effort_now":{"value":30.4,"scale":"0-100","source":"NOOP (strap)"}},
        "planned":[{"name":"Synthetic tempo run","type":"tempo","sport":"run","minutes":50,"hard":true,"done":false}],
        "lead_session":null,"tomorrow_session":{"name":"Synthetic easy run","type":"easy_run","sport":"run","minutes":40,"hard":false,"done":false},
        "load":{"acwr":1.1,"flag":"ok","high":false},"call":"keep","verdict":"Synthetic verdict."},
       "status":{"label":"keep","scale":["ease","keep","go"],"threshold":"synthetic","reason":null},
       "meaning":"Charge 72 (green, NOOP) and readiness 41 (yellow, PaceForge/Garmin): the scores differ, keep the planned tempo run but stay at the low end of the range.",
       "actions":[{"id":"keep_plan","text":"Do the tempo run as planned and stop at the low end of the Effort range.","why":"Charge is green and readiness is yellow.","effort":{"value":0,"unit":"min","label":"no extra time"},"impact":3,"topic":"training","tags":["suggestion"]}],
       "confidence":"medium","data_note":"Charge is NOOP's score from the strap, readiness is PaceForge's from the watch; they are not averaged.","source":["NOOP","PaceForge"]}
     }}
    """

    static var intel: PFDailyIntel? { PFDailyIntelParse.document(PFJ(data: Data(json.utf8))) }
}

#Preview("Today's call") {
    ScrollView {
        if let intel = PFIntelSample.intel, let call = intel.call, let item = intel.callItem {
            PFTodaysCallCard(call: call, item: item)
                .padding(16)
        }
    }
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}

#Preview("Health monitor tile") {
    VStack(spacing: 12) {
        PFHealthMonitorTile(tile: PFHealthTile(state: .withinRange, status: "WITHIN RANGE", detail: "4/4 metrics", isRed: false))
        PFHealthMonitorTile(tile: PFHealthTile(state: .alert, status: "VERY ELEVATED", detail: "Respiratory rate", isRed: true))
    }
    .padding(16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}

#Preview("Vital row") {
    VStack(spacing: 0) {
        PFVitalRow(vital: PFVital(key: "resp", label: "Respiratory rate", unit: "br/min", source: "NOOP", available: true,
                                  value: 19.2, nights: 28, typicalLow: 13.5, typicalHigh: 16.5, typicalCenter: 15,
                                  z: 2.8, status: "elevated", word: "VERY ELEVATED", illnessDirection: true, reason: nil))
        PFVitalRow(vital: PFVital(key: "hrv", label: "HRV", unit: "ms", source: "Garmin", available: true, value: 41,
                                  nights: 23, typicalLow: 29, typicalHigh: 41, typicalCenter: 35, z: 1.0, status: "within",
                                  word: "WITHIN RANGE", illnessDirection: false, reason: nil))
    }
    .padding(.horizontal, 16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
