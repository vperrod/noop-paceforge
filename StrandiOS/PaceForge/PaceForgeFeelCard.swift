import SwiftUI
import StrandDesign

// The morning check-in and the "what changed" card on PaceForge Today.
//
// Colour rule for this file: nothing here is red or green. A feeling that differs from a score, or a number
// that moved, is information, not a grade, so direction and agreement use the neutral blue-grey, violet and
// grey of the palette and always carry a word or an arrow as well.

enum PFNeutral {
    /// Things that matched, or moved in the direction the server calls better.
    static var main: Color { PFColor.sky }
    /// Things that differ or moved the other way.
    static var other: Color { PFColor.violet }
    /// Flat, unknown or higher-than-expected.
    static var quiet: Color { StrandPalette.textSecondary }

    static func agreement(_ value: String?) -> Color {
        switch value {
        case "match": return main
        case "feel_lower": return other
        default: return quiet
        }
    }

    static func tone(_ value: String) -> Color {
        switch value {
        case "better": return main
        case "worse": return other
        default: return quiet
        }
    }
}

// MARK: How do you feel?

struct PFFeelCard: View {
    let feel: PFFeelSummary
    let todayISO: String

    @EnvironmentObject private var model: PFModel
    @State private var isSaving = false
    @State private var didFail = false

    private static let words = ["awful", "poor", "okay", "good", "great"]

    /// A summary built for an earlier day says nothing about today's answer.
    private var isCurrent: Bool { feel.date == nil || feel.date == todayISO }
    private var selected: Int? { isCurrent && feel.answered ? feel.feel : nil }

    var body: some View {
        PFCard(title: "How do you feel?", icon: "face.smiling", info: PFExplainerID.feel, trailing: {
            if let selected {
                PFChip(text: "Saved \u{00B7} \(selected) of 5", color: PFNeutral.main)
                    .accessibilityIdentifier("pf-feel-saved")
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                PFParagraph(selected == nil ? "One tap, 1 to 5. It is kept beside your score and never changes it."
                                            : "Tap another number to change today's answer.")
                buttons
                if didFail {
                    Label("Couldn't save \u{2014} try again", systemImage: "exclamationmark.circle")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(PFColor.warning)
                        .accessibilityIdentifier("pf-feel-error")
                }
                if let sentence = feel.sentence {
                    Text(sentence)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-feel-sentence")
                }
                if feel.days.contains(where: { $0.feel != nil }) { PFFeelStrip(days: feel.days) }
            }
        }
        .containerIdentifier("pf-feel-card")
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button { tap(value) } label: {
                    VStack(spacing: 2) {
                        Text("\(value)")
                            .font(StrandFont.rounded(22))
                            .foregroundStyle(selected == value ? StrandPalette.goldDeepText : StrandPalette.textPrimary)
                        Text(Self.words[value - 1])
                            .font(StrandFont.caption)
                            .foregroundStyle(selected == value ? StrandPalette.goldDeepText : StrandPalette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected == value ? StrandPalette.accent : StrandPalette.surfaceInset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StrandPalette.hairline, lineWidth: selected == value ? 0 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel("Feel \(value) of 5, \(Self.words[value - 1])")
                .accessibilityAddTraits(selected == value ? .isSelected : [])
                .accessibilityIdentifier("pf-feel-\(value)")
            }
        }
    }

    private func tap(_ value: Int) {
        guard !isSaving else { return }
        isSaving = true
        didFail = false
        Task { @MainActor in
            let saved = await model.submitFeel(value)
            didFail = !saved
            isSaving = false
        }
    }
}

/// The last 14 days as dots: coloured by how the feeling compared with the score's band that day, hollow
/// when there was no answer.
private struct PFFeelStrip: View {
    let days: [PFFeelDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(days) { dot($0) }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                legend(PFNeutral.main, "matched the score")
                legend(PFNeutral.other, "felt lower")
                legend(PFNeutral.quiet, "felt higher")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .containerIdentifier("pf-feel-strip")
    }

    @ViewBuilder private func dot(_ day: PFFeelDay) -> some View {
        if day.feel == nil {
            Circle().stroke(StrandPalette.hairline, lineWidth: 1.5).frame(width: 12, height: 12)
        } else if day.agreement != nil {
            Circle().fill(PFNeutral.agreement(day.agreement)).frame(width: 12, height: 12)
        } else {
            // Answered, but no score that day to compare with.
            Circle().fill(StrandPalette.textTertiary.opacity(0.5)).frame(width: 12, height: 12)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private var summary: String {
        let matched = days.filter { $0.agreement == "match" }.count
        let lower = days.filter { $0.agreement == "feel_lower" }.count
        let higher = days.filter { $0.agreement == "feel_higher" }.count
        return "Last 14 days: \(matched) matched the score, \(lower) felt lower, \(higher) felt higher."
    }
}

// MARK: What changed since yesterday

struct PFWhatChangedCard: View {
    let changes: PFWhatChanged

    @State private var openRow: String?

    private static let maxRows = 6

    /// Metrics that moved come first; the rest keep the server's order.
    private var rows: [PFChangeMetric] {
        let moved = changes.metrics.filter { $0.direction == "up" || $0.direction == "down" }
        let rest = changes.metrics.filter { !($0.direction == "up" || $0.direction == "down") }
        return Array((moved + rest).prefix(Self.maxRows))
    }

    var body: some View {
        PFCard("What changed since yesterday", icon: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 0) {
                if let summary = changes.summary {
                    Text(summary)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("pf-changes-summary")
                }
                ForEach(rows) { metric in
                    Divider().overlay(StrandPalette.hairline)
                    row(metric)
                }
            }
        }
        .containerIdentifier("pf-changes-card")
    }

    private func row(_ metric: PFChangeMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { openRow = openRow == metric.id ? nil : metric.id }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.label)
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .multilineTextAlignment(.leading)
                            if let line = calibrationLine(metric) {
                                Text(line)
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(PFColor.sky)
                                    .accessibilityIdentifier("pf-change-calibration-\(metric.id)")
                            } else if let source = metric.source, source != "PaceForge" {
                                Text(source).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        figures(metric)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pf-change-\(metric.id)")
                if let explainer = PFExplainerID.forChange(metric.id) { PFInfoButton(id: explainer) }
            }
            if openRow == metric.id { detail(metric) }
        }
        .padding(.vertical, 9)
    }

    /// The "Day 12 of 21" line, shown while the metric is still calibrating.
    private func calibrationLine(_ metric: PFChangeMetric) -> String? {
        guard metric.calibrating else { return nil }
        return metric.calibration?.line ?? changes.calibrating.first { $0.id == metric.id }?.line
    }

    private func figures(_ metric: PFChangeMetric) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.value.map(Self.number) ?? "\u{2013}")
                    .font(StrandFont.rounded(20))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let unit = Self.shownUnit(metric.unit) {
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            if metric.value != nil { deltaLabel(metric) }
        }
    }

    @ViewBuilder private func deltaLabel(_ metric: PFChangeMetric) -> some View {
        let color = PFNeutral.tone(metric.tone)
        HStack(spacing: 3) {
            Image(systemName: Self.arrow(metric.direction))
                .font(.system(size: 10, weight: .bold))
            if let delta = metric.delta, metric.direction == "up" || metric.direction == "down" {
                Text(Self.number(abs(delta)))
            } else {
                Text(metric.direction == "flat" ? "steady" : "no change data")
            }
        }
        .font(StrandFont.caption.weight(.semibold))
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deltaAccessibility(metric))
    }

    @ViewBuilder private func detail(_ metric: PFChangeMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reason = metric.reason { PFParagraph(reason) }
            if let typical = metric.typical, let low = typical.low, let high = typical.high {
                Text("Usual \(Self.number(low))\u{2013}\(Self.number(high))" + (typical.basis.map { " (\($0))" } ?? ""))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if let previous = metric.previous {
                Text("\(PFFormat.capitalized(metric.previousLabel ?? "yesterday")): \(Self.number(previous))")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if let calibration = metric.calibration, !calibration.ready { PFCalibrationBar(calibration: calibration) }
        }
        .padding(.top, 2)
        .containerIdentifier("pf-change-detail-\(metric.id)")
    }

    // MARK: Formatting

    static func number(_ value: Double) -> String {
        if value.rounded() == value || abs(value) >= 100 { return String(Safe.int(value)) }
        return PFFormat.oneDecimal(value)
    }

    private static func shownUnit(_ unit: String) -> String? {
        ["", "pts", "0-21"].contains(unit) ? nil : unit
    }

    private static func arrow(_ direction: String) -> String {
        switch direction {
        case "up": return "arrow.up"
        case "down": return "arrow.down"
        case "flat": return "equal"
        default: return "questionmark"
        }
    }

    private func deltaAccessibility(_ metric: PFChangeMetric) -> String {
        switch (metric.direction, metric.delta) {
        case ("up", let delta?): return "Up \(Self.number(abs(delta)))"
        case ("down", let delta?): return "Down \(Self.number(abs(delta)))"
        case ("flat", _): return "Steady"
        default: return "No change data"
        }
    }
}

// MARK: Readiness answers and trust

/// "OK to train: yes" / "OK to train hard: careful", each with its reason underneath.
struct PFAnswersView: View {
    let answers: PFAnswers

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let train = answers.train { column("OK to train", train, id: "pf-answer-train") }
            if let hard = answers.trainHard { column("OK to train hard", hard, id: "pf-answer-hard") }
            if let planned = answers.plannedName {
                Text("Planned: \(planned)" + (answers.plannedHard ? " (a hard session)" : ""))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if answers.plannedOverload {
                Text("This is a planned overload block, so low scores lower the first answer to careful, not to no.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .containerIdentifier("pf-answers")
    }

    private func column(_ title: String, _ answer: PFAnswer, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            PFChip(text: "\(title): \(answer.level.word)", color: Self.color(answer.level))
            if let reason = answer.reason {
                Text(reason)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private static func color(_ level: PFAnswerLevel) -> Color {
        switch level {
        case .yes: return PFNeutral.main
        case .careful: return PFNeutral.other
        case .no: return PFNeutral.quiet
        }
    }
}

/// A chip reading "Low confidence: the watch recorded only 40% of the night" (wrapping, not truncated).
/// Draws nothing for a reading that is fine.
struct PFTrustNote: View {
    let trust: PFTrust?

    var body: some View {
        if let text = trust?.text {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PFNeutral.other)
                Text(text)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PFNeutral.other.opacity(0.12)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .containerIdentifier("pf-trust-note")
        }
    }
}
