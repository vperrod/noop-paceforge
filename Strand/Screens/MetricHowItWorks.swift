import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - "How it works" for HRV, Stress and Vital Signs
//
// The scoring guide explains Charge, Effort and Rest. The cards that feed them, HRV, the Stress monitor and
// the Vital Signs grid, had no explanation of their own, so each gets a small ⓘ that opens a short sheet in
// the guide's own layout (fixed header with a close button, NoopCard sections, "Got it" footer). Every
// sentence below restates what the code does; nothing is a formula of its own.

enum MetricTopic: String, Identifiable {
    case hrv, stress, vitals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: return String(localized: "HRV")
        case .stress: return String(localized: "Stress monitor")
        case .vitals: return String(localized: "Vital Signs")
        }
    }

    var tint: Color {
        switch self {
        case .hrv: return StrandPalette.metricPurple
        case .stress: return StrandPalette.restColor
        case .vitals: return StrandPalette.chargeColor
        }
    }

    /// Heading + body pairs, in reading order.
    var sections: [(heading: String, body: String)] {
        switch self {
        case .hrv:
            return [
                (String(localized: "What it is"),
                 String(localized: "Heart-rate variability is how much the time between heartbeats varies. NOOP measures it as RMSSD from the strap's beat-to-beat (R-R) intervals, after dropping beats that fall outside a plausible range or look like ectopic beats.")),
                (String(localized: "How NOOP uses it"),
                 String(localized: "Your HRV is compared with your own baseline, not a population number. Higher than your usual leans toward more Charge, lower toward less; it is the lead input to Charge.")),
                (String(localized: "Good to know"),
                 String(localized: "One night is noisy. Alcohol, a late meal, heat, illness and a hard evening all move it, so read the trend rather than a single reading.")),
            ]
        case .stress:
            return [
                (String(localized: "What it is"),
                 String(localized: "A 0 to 3 read of how much strain your autonomic nervous system shows: 0 to 1 low, 1 to 2 medium, 2 to 3 high, with 1.5 being your usual.")),
                (String(localized: "How the day's number is built"),
                 String(localized: "Today's resting heart rate and HRV are compared with your own 30-day baseline. A higher resting heart rate and a lower HRV both push the score up. A signal with fewer than two earlier nights has no spread to compare with, so it adds nothing.")),
                (String(localized: "Through the day"),
                 String(localized: "The timeline scores each waking hour from its mean heart rate and its HRV against the calmest hours of the same day, on the same 0 to 3 scale. An hour with too little data is not scored, and an hour of exertion is masked rather than read as stress.")),
                (String(localized: "Good to know"),
                 String(localized: "It is an approximate proxy, not a diagnosis.")),
            ]
        case .vitals:
            return [
                (String(localized: "What it is"),
                 String(localized: "The latest nightly vital signs your data has: resting heart rate, HRV, respiratory rate, skin temperature and, where available, blood oxygen. A reading is carried forward for up to a week to survive a missed night, then shows a dash.")),
                (String(localized: "What \"in range\" means"),
                 String(localized: "Once your baseline is trusted (14 valid nights and not stale), in range means within two standard deviations of your own recent baseline, about 95% of your normal nights. Until then, typical adult ranges apply.")),
                (String(localized: "Good to know"),
                 String(localized: "These are approximate and informational, not medical advice.")),
            ]
        }
    }

    /// The Charge section of the scoring guide uses HRV and resting HR; the other topics have no section.
    var guideSection: ScoreSection? {
        switch self {
        case .hrv, .vitals: return .charge
        case .stress: return nil
        }
    }
}

/// The "N nights to go" copy. Counts come from the engine's own constants, so a change there changes the
/// sentence. nil when the baseline is already trusted, or when the engine has no minimum to wait for.
enum MetricCalibration {
    static func nightsToGo(_ nights: Int) -> String {
        nights == 1 ? String(localized: "1 night to go") : String(localized: "\(nights) nights to go")
    }

    /// The HRV baseline: unusable under `seed` valid nights, provisional until `trust`.
    static func hrvLine(nights: Int, seed: Int = Baselines.minNightsSeed, trust: Int = Baselines.minNightsTrust) -> String? {
        if nights < seed {
            return String(localized: "\(nightsToGo(seed - nights)) before Charge can use your HRV baseline. It is fully trusted after \(trust) nights.")
        }
        if nights < trust {
            return String(localized: "Your baseline is provisional: \(nightsToGo(trust - nights)) until it is fully trusted.")
        }
        return nil
    }

    /// Vital Signs compare with the user's own baseline only once it has `trust` valid nights.
    static func vitalsLine(nights: Int, trust: Int = Baselines.minNightsTrust) -> String? {
        guard nights < trust else { return nil }
        return String(localized: "\(nightsToGo(trust - nights)) until in range compares each vital with your own baseline. Typical adult ranges apply until then.")
    }

    static func line(for topic: MetricTopic, hrvNights: Int) -> String? {
        switch topic {
        case .hrv: return hrvLine(nights: hrvNights)
        case .vitals: return vitalsLine(nights: hrvNights)
        case .stress: return nil
        }
    }
}

/// A small ⓘ that opens the sheet for `topic`. Owns its own presentation state, so it drops into a tile
/// header or a section footer without the host view carrying anything.
struct MetricInfoButton: View {
    let topic: MetricTopic
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("How \(topic.title) works"))
        .accessibilityIdentifier("metric-info-\(topic.rawValue)")
        .sheet(isPresented: $isShowing) { MetricHowItWorksSheet(topic: topic, onClose: { isShowing = false }) }
    }
}

struct MetricHowItWorksSheet: View {
    let topic: MetricTopic
    let onClose: () -> Void

    @EnvironmentObject private var repo: Repository
    @State private var showGuide = false

    /// Nights with an HRV reading: the series every baseline in these cards is learned from.
    private var hrvNights: Int { repo.days.compactMap(\.avgHrv).filter { $0 > 0 }.count }

    var body: some View {
        VStack(spacing: 0) {
            header.background(NoopChromeSurface())
            Divider().overlay(StrandPalette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    ForEach(Array(topic.sections.enumerated()), id: \.offset) { _, section in
                        card(section.heading, section.body)
                    }
                    if let line = MetricCalibration.line(for: topic, hrvNights: hrvNights) { calibrationCard(line) }
                    if topic.guideSection != nil { guideButton }
                }
                .padding(20)
            }
            Divider().overlay(StrandPalette.hairline)
            footerBar
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .noopSheetPresentation(largeFirst: false)
        #endif
        .background(StrandPalette.surfaceBase)
        .sheet(isPresented: $showGuide) {
            ScoringGuideView(initialSection: topic.guideSection, onClose: { showGuide = false })
        }
        .accessibilityIdentifier("metric-how-\(topic.rawValue)")
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOW IT WORKS").font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text(topic.title).font(StrandFont.rounded(26, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    private func card(_ heading: String, _ text: String) -> some View {
        NoopCard(tint: topic.tint) {
            VStack(alignment: .leading, spacing: 8) {
                Text(heading).font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(topic.tint)
                Text(text).font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func calibrationCard(_ line: String) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                StatePill("Calibrating", tone: .neutral, showsDot: true)
                Text(line).font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("metric-calibration")
    }

    private var guideButton: some View {
        Button { showGuide = true } label: {
            Label("How Charge is calculated", systemImage: "info.circle")
                .font(StrandFont.subhead)
        }
        .buttonStyle(.bordered)
        .tint(StrandPalette.accent)
    }

    private var footerBar: some View {
        HStack {
            AskCoachButton(metric: topic.title, onClose: onClose)
            Spacer()
            Button(action: onClose) {
                Text("Got it").frame(minWidth: 120).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(StrandPalette.accent)
        }
        .padding(16)
    }
}
