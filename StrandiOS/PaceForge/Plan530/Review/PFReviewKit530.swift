import SwiftUI
import StrandDesign

// The parts the Sunday review shares (screens 1b to 1e): its colours, the card a chart sits in with its one reading line under it, and
// the small text helpers. The tile, pills and buttons are the Week screens' own (`pfWeekCard`, `PFWeekPills529`, `PFWeekButton529`).

enum PFReviewColor530 {
    /// The violet of the drawings (sleep that met the need is blue, short nights are violet).
    static let violet = Color(hex: "#A99CFF")
}

enum PFReviewFormat530 {
    /// "46" from "2026-W46".
    static func weekNumber(_ isoWeek: String) -> String {
        guard let at = isoWeek.range(of: "W") else { return isoWeek }
        let digits = String(isoWeek[at.upperBound...].prefix { $0.isNumber })
        return Int(digits).map(String.init) ?? digits
    }

    /// "9 to 15 Nov", or "28 Oct to 3 Nov" across a month.
    static func range(from: String?, to: String?) -> String? {
        guard let from, let to, from.count >= 10, to.count >= 10 else { return nil }
        let start = PFFormat.shortDate(from), end = PFFormat.shortDate(to)
        let startParts = start.split(separator: " "), endParts = end.split(separator: " ")
        if let startMonth = startParts.last, startMonth == endParts.last, let day = startParts.first {
            return "\(day) to \(end)"
        }
        return "\(start) to \(end)"
    }

    /// "+45 s", or "+1:05" from a minute up.
    static func lost(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total < 60 ? "+\(total) s" : String(format: "+%d:%02d", total / 60, total % 60)
    }

    /// The first sentence of a text, with its full stop; the whole text when it has one sentence.
    static func firstSentence(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        guard let stop = text.range(of: ". ") else { return text }
        return String(text[..<stop.upperBound]).trimmingCharacters(in: .whitespaces)
    }

    /// The label of a mix type.
    static func mixLabel(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "classes": return "Classes and HYROX"
        case "strength": return "Strength"
        case "running": return "Running"
        case "cycling": return "Cycling"
        case "other": return "Other"
        default: return PFFormat.capitalized(type ?? "")
        }
    }

    static func mixColor(_ type: String?) -> Color {
        switch (type ?? "").lowercased() {
        case "classes": return PFWeekColor529.amber
        case "strength": return PFReviewColor530.violet
        case "running": return PFWeekColor529.teal
        case "cycling": return PFWeekColor529.blue
        default: return NoopLook.textSecondary
        }
    }

    /// The colour of a season phase in the calendar bar: recover teal, build blue, sharpen violet, taper amber.
    static func phaseColor(_ phase: String?) -> Color {
        switch (phase ?? "").lowercased() {
        case "recover", "recovery", "rest": return PFWeekColor529.teal.opacity(0.55)
        case "build": return PFWeekColor529.blue
        case "sharpen", "sharpening": return PFReviewColor530.violet
        case "taper": return PFWeekColor529.amber
        case "race": return PFWeekColor529.red
        default: return NoopLook.textSecondary
        }
    }
}

extension View {
    /// A chart's tile (the Week screens' card), named `review530-chart-<key>` for tests. Each chart writes its own VStack: title overline,
    /// chart, `PFReviewReading530`. No generic container: a generic card carries every screen's view tree in its type name (build 472).
    func pfReviewCard530(_ key: String) -> some View {
        self.pfWeekCard().containerIdentifier("review530-chart-\(key)")
    }
}

/// The reading line under a chart.
struct PFReviewReading530: View {
    let key: String
    let text: String?
    private let hiding = PFHiding()

    var body: some View {
        if let text, !text.isEmpty {
            Text(attributed(hiding.text(text)))
                .font(PFPlanFont543.text(13.5, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("review530-reading-\(key)")
        }
    }

    /// Two sentences or more: the first one in bold, as drawn.
    private func attributed(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        guard let stop = text.range(of: ". ") else { return out }
        let lead = String(text[..<text.index(before: stop.upperBound)])
        if let range = out.range(of: lead) {
            out[range].font = PFPlanFont543.text(13.5, weight: .semibold)
            out[range].foregroundColor = NoopLook.textPrimary
        }
        return out
    }
}

/// The big headline of a half of the page.
struct PFReviewHeadline530: View {
    let text: String
    let identifier: String
    private let hiding = PFHiding()

    var body: some View {
        Text(hiding.text(text))
            .font(PFPlanFont543.text(22, weight: .bold))
            .foregroundStyle(NoopLook.textPrimary)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }
}

/// The title that opens a part of the page ("Week 46 · your body").
struct PFReviewSectionTitle530: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PFPlanFont543.text(17, weight: .semibold))
            .foregroundStyle(NoopLook.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A full-width pill button ("Accept week 47").
struct PFReviewWideButton530: View {
    let title: String
    var isDisabled = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .pfCaps(12, weight: .semibold)
                .foregroundStyle(Color(hex: "#06231A"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Capsule(style: .continuous).fill(PFWeekColor529.teal))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// The pills under the page title: side by side, or one under the other when they do not fit (the flow layout of the Week screens drew
/// a wrapped second pill over the text below it).
struct PFReviewPills530: View {
    let pills: [(text: String, color: Color)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chips
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
            PFChip(text: pill.text, color: pill.color)
        }
    }
}
