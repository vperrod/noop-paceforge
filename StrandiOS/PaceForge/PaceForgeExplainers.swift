import SwiftUI
import StrandDesign

// "How it works": the plain-language sheet behind an (i) button on a PaceForge card, built from the
// server's metric-explainers.json. A card shows the button only when the server has an entry for it, so an
// older server just has no buttons.

// MARK: Environment

private struct PFExplainersKey: EnvironmentKey {
    static let defaultValue: [String: PFExplainer] = [:]
}

extension EnvironmentValues {
    /// The metric explainers by id, set once on the PaceForge screens.
    var pfExplainers: [String: PFExplainer] {
        get { self[PFExplainersKey.self] }
        set { self[PFExplainersKey.self] = newValue }
    }
}

extension PFSnapshot {
    var explainerMap: [String: PFExplainer] {
        Dictionary(explainers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The "Day 3 of 5" line for a metric whose explainer says it is not ready yet, else nil.
    func calibrationLine(_ id: String) -> String? {
        guard let calibration = explainer(id)?.calibration, !calibration.ready else { return nil }
        return calibration.line
    }
}

/// Which explainer each card or number uses. The ids are the server's (`explainers.py`).
enum PFExplainerID {
    static let recovery = "recovery"
    static let strain = "strain"
    static let sleepScore = "sleep_score"
    static let sleepNeed = "sleep_need_debt"
    static let hrv = "hrv_status"
    static let restingHr = "resting_hr"
    static let load = "load_ramp"
    static let readinessSources = "readiness_sources"
    static let garminReadiness = "garmin_readiness"
    static let noopRecovery = "noop_recovery"
    static let answers = "answers"
    static let feel = "feel"
    static let lowConfidence = "low_confidence"
    static let behaviour = "behaviour_impact"
    static let bodyWeightTrend = "body_weight_trend"
    static let bodyFatTrend = "body_fat_trend"
    static let bodyNoiseBand = "body_noise_band"
    static let bodyEstimates = "body_estimates"
    static let hrrContextBand = "hrr1_context_band"

    /// The "what changed" row ids -> explainer ids.
    static func forChange(_ metricId: String) -> String? {
        switch metricId {
        case "recovery_pf": return recovery
        case "hrv_7d": return hrv
        case "rhr": return restingHr
        case "sleep_hours": return sleepNeed
        case "sleep_score": return sleepScore
        case "strain": return strain
        case "load_week": return load
        case "weight_trend": return bodyWeightTrend
        case "readiness_garmin": return garminReadiness
        case "readiness_noop": return noopRecovery
        default: return nil
        }
    }

    /// A readiness source's own explainer; PaceForge's is the shared "three scores" one.
    static func forReadinessSource(_ source: String) -> String {
        switch source {
        case "Garmin": return garminReadiness
        case "NOOP": return noopRecovery
        default: return readinessSources
        }
    }

    /// The heart-rate-recovery explainer for a kind: post, interval, walking or not_measurable.
    static func forHRR1(kind: String) -> String {
        switch kind {
        case PFHRR1.interval: return "hrr1_interval"
        case PFHRR1.walking: return "hrr1_walking"
        case PFHRR1.notMeasurable: return "hrr1_not_measurable"
        default: return "hrr1_post"
        }
    }
}

// MARK: Button

/// A small (i) that opens the explainer sheet for `id`. Draws nothing when the server has no such entry.
struct PFInfoButton: View {
    let id: String
    @Environment(\.pfExplainers) private var explainers
    @State private var isShowing = false

    var body: some View {
        if let explainer = explainers[id] {
            Button { isShowing = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How \(explainer.title) works")
            .accessibilityIdentifier("pf-info-\(id)")
            .sheet(isPresented: $isShowing) { PFExplainerSheet(explainer: explainer) }
        }
    }
}

// MARK: Sheet

struct PFExplainerSheet: View {
    let explainer: PFExplainer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let plain = explainer.plain {
                        Text(plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pf-explainer-plain")
                    }
                    section("How it is made", explainer.how)
                    section("Usual range", explainer.usualRange)
                    section("Worth knowing", explainer.caveat)
                    unlockSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(explainer.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("pf-explainer-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("pf-explainer-sheet")
    }

    @ViewBuilder private func section(_ title: String, _ text: String?) -> some View {
        if let text {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).strandOverline()
                PFParagraph(text)
            }
        }
    }

    @ViewBuilder private var unlockSection: some View {
        if explainer.unlocks != nil || explainer.calibration != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("When it unlocks").strandOverline()
                if let unlocks = explainer.unlocks { PFParagraph(unlocks) }
                if let calibration = explainer.calibration { PFCalibrationBar(calibration: calibration) }
            }
        }
    }
}

// MARK: Calibration

/// "Day 12 of 21" with a progress bar. A metric that is ready shows no bar.
struct PFCalibrationBar: View {
    let calibration: PFCalibration

    var body: some View {
        if let line = calibration.line {
            VStack(alignment: .leading, spacing: 6) {
                Text(line)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !calibration.ready {
                    ProgressView(value: calibration.fraction)
                        .tint(PFColor.sky)
                        .accessibilityLabel(line)
                        .accessibilityIdentifier("pf-calibration-bar")
                }
            }
        }
    }
}

// MARK: Insights list

/// Every explainer the server has, as a list that opens the same sheet. A metric still calibrating says so.
struct PFHowScoresWorkCard: View {
    let explainers: [PFExplainer]
    @State private var selected: PFExplainer?

    var body: some View {
        if !explainers.isEmpty {
            PFCard("How these scores work", icon: "questionmark.circle") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(explainers) { explainer in
                        Button { selected = explainer } label: { row(explainer) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pf-how-\(explainer.id)")
                        if explainer.id != explainers.last?.id { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
            .accessibilityIdentifier("pf-how-scores-work")
            .sheet(item: $selected) { PFExplainerSheet(explainer: $0) }
        }
    }

    private func row(_ explainer: PFExplainer) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(explainer.title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let plain = explainer.plain {
                    Text(plain)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let calibration = explainer.calibration, !calibration.ready, let line = calibration.line {
                    Text(line)
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(PFColor.sky)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(.top, 3)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
