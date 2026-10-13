import SwiftUI
import StrandDesign

// The newer PaceForge cards on Today and in session results: open alerts, the three readiness reads and
// heart-rate recovery. Each one is drawn only when its file is present, so an older server shows nothing new.

// MARK: Alerts

/// Open alerts with a severity stripe. The app is read-only: an alert's actions are shown as labels and
/// answered in Telegram.
struct PFAlertsCard: View {
    let alerts: [PFAlert]

    var body: some View {
        PFCard(title: "Alerts", icon: "exclamationmark.triangle.fill", trailing: {
            PFChip(text: "\(alerts.count) open", color: alerts.contains { $0.severity == "act" } ? PFColor.critical : PFColor.warning)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(alerts) { alert in
                    PFAlertRow(alert: alert)
                }
                if alerts.contains(where: { !$0.actions.isEmpty }) {
                    Text("Answer in Telegram. This app only shows the alert.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .containerIdentifier("pf-alerts-card")
    }
}

private struct PFAlertRow: View {
    let alert: PFAlert

    private var color: Color {
        switch alert.severity {
        case "act": return PFColor.critical
        case "watch": return PFColor.warning
        default: return PFColor.sky
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(alert.title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = alert.body {
                    Text(body)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !alert.actions.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6, alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(alert.actions) { action in
                            PFChip(text: action.label, color: StrandPalette.textTertiary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Readiness

/// PaceForge's, Garmin's and NOOP's readiness side by side. They measure different things, so there is
/// deliberately no combined number.
struct PFReadinessCard: View {
    let readiness: PFReadiness

    var body: some View {
        PFCard("Why my readiness is this", icon: "gauge.with.dots.needle.67percent",
               info: PFExplainerID.readinessSources) {
            VStack(alignment: .leading, spacing: 14) {
                if let answers = readiness.answers { PFAnswersView(answers: answers) }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(readiness.sources) { PFReadinessColumn(source: $0) }
                }
                if let agreement = readiness.agreement {
                    HStack(spacing: 8) {
                        PFChip(text: Self.agreementText(agreement), color: Self.agreementColor(agreement))
                        Text("Three separate reads, never averaged.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if let note = readiness.coachNote { PFParagraph(note) }
            }
        }
        .containerIdentifier("pf-readiness-card")
    }

    private static func agreementText(_ value: String) -> String {
        switch value {
        case "agree": return "All three agree"
        case "mixed": return "Mixed"
        case "disagree": return "They disagree"
        default: return PFFormat.capitalized(value)
        }
    }

    private static func agreementColor(_ value: String) -> Color {
        switch value {
        case "agree": return PFColor.positive
        case "disagree": return PFColor.critical
        default: return PFColor.warning
        }
    }
}

private struct PFReadinessColumn: View {
    let source: PFReadinessSource

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Text(source.source).strandOverline()
                if source.source != "PaceForge" { PFInfoButton(id: PFExplainerID.forReadinessSource(source.source)) }
            }
            Text(source.score.map { String(Int($0.rounded())) } ?? "\u{2013}")
                .font(StrandFont.rounded(28))
                .foregroundStyle(StrandPalette.textPrimary)
            if let band = source.band {
                PFChip(text: PFFormat.capitalized(band), color: PFColor.sky)
            }
            PFTrustNote(trust: source.trust)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The few facts each source brings: its drivers, factors, or the NOOP inputs.
    private var lines: [String] {
        var out: [String] = source.drivers.prefix(3).map { $0 }
        out += source.factors.prefix(4).map { factor in
            [factor.name, factor.value].compactMap { $0 }.joined(separator: " ")
                + (factor.status.map { " (\($0))" } ?? "")
        }
        if let hours = source.recoveryTimeH { out.append("Recovery time \(PFFormat.trimmed(hours)) h") }
        if let hrv = source.hrv { out.append("HRV \(PFFormat.trimmed(hrv)) ms") }
        if let rhr = source.rhr { out.append("Resting HR \(PFFormat.trimmed(rhr))") }
        if let sleep = source.sleepPerformance { out.append("Sleep \(PFFormat.trimmed(sleep))%") }
        return out
    }
}

// MARK: Heart-rate recovery

/// First-minute heart-rate recovery for a completed session. The population context band is a neutral
/// caption; only the athlete's own band (scored kinds with a baseline) gets a coloured pill.
struct PFHRR1Card: View {
    let hrr: PFHRR1

    var body: some View {
        PFCard(title: "Heart rate recovery", icon: "heart.text.square", info: PFExplainerID.forHRR1(kind: hrr.kind), trailing: {
            if let band = hrr.personalBand { PFChip(text: PFFormat.capitalized(band), color: Self.color(band)) }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                if showsDrop, let bpm = hrr.bpm {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(bpm)")
                            .font(StrandFont.rounded(34))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("bpm in the first minute")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                PFParagraph(explainer)
                HStack(alignment: .top, spacing: 18) {
                    if let stop = hrr.stopBpm { PFFigure(value: "\(stop)", unit: "bpm", label: "At the stop") }
                    if let peak = hrr.peakBpm { PFFigure(value: "\(peak)", unit: "bpm", label: "Peak") }
                    if hrr.isScored, let two = hrr.bpm120 { PFFigure(value: "\(two)", unit: "bpm", label: "By 2 min") }
                    if hrr.isScored, let base = hrr.baselineBpm { PFFigure(value: PFFormat.trimmed(base), unit: "bpm", label: "Your usual") }
                    if hrr.isScored, hrr.baselineBpm != nil, let delta = hrr.delta {
                        PFFigure(value: (delta > 0 ? "+" : "") + PFFormat.oneDecimal(delta), unit: "bpm", label: "Versus usual")
                    }
                }
                if let context = contextCaption {
                    HStack(alignment: .top, spacing: 4) {
                        Text(context)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pf-hrr1-context")
                        PFInfoButton(id: PFExplainerID.hrrContextBand)
                    }
                }
            }
        }
        .containerIdentifier("pf-hrr1")
    }

    /// The big first-minute number is for real stops only; a cool-down gets the explanation line instead.
    private var showsDrop: Bool { hrr.isScored && !hrr.isNotScoredCoolDown }

    private var explainer: String {
        if hrr.isNotScoredCoolDown { return PFHRR1.notScoredLine }
        switch hrr.kind {
        case PFHRR1.interval:
            return "Interval rebound \u{2014} compared with your own intervals." + (hrr.isEstimated ? " Estimated." : "")
        case PFHRR1.notMeasurable:
            return "Not enough readings after the end."
        default:
            return "How far your heart rate fell in the first minute after you stopped."
        }
    }

    /// Population context for a one-minute drop after stopping; never a grade, so it is never coloured.
    private var contextCaption: String? {
        guard hrr.kind == PFHRR1.post, let band = hrr.contextBand else { return nil }
        switch band {
        case "flag": return "For context: a drop of 12 bpm or less in the first minute is below the usual range."
        case "low": return "For context: a drop of 13 to 18 bpm in the first minute is on the low side of the usual range."
        case "typical": return "For context: a drop of 19 to 30 bpm in the first minute is typical."
        case "strong": return "For context: a drop above 30 bpm in the first minute is strong."
        default: return nil
        }
    }

    static func color(_ band: String) -> Color {
        switch band {
        case "good": return PFColor.positive
        case "watch": return PFColor.warning
        case "flag": return PFColor.critical
        default: return PFColor.sky
        }
    }
}
