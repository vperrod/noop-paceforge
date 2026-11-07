import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Effort target (Today card, Strain card line, widget feed)
//
// Today's Effort against the band NOOP already shows as OPTIMAL: "Effort 42 of 67–86: 25–44 to go", plus a
// Training State word. NOOP's own 0–100 Effort scale (or the 0–21 scale when the user chose it), no other
// app's numbers. Presentation only: nothing here feeds a score. The maths is `EffortTarget` in
// StrandAnalytics; this file reads the repository, reuses `CoupledView.optimalStrainRange` for the band, and
// draws. The existing "optimal strain reached" notification is untouched.

/// Everything the card, the Strain-card line and the widget publish need, built once from the day rows.
struct EffortTargetReading: Equatable {
    var progress: EffortTarget.Progress
    var training: EffortTarget.TrainingStateReading
    /// The Charge the band came from: today's, else the last scored one (the same carry the Coupled view uses).
    var recovery: Double?
    /// The logical day the reading describes (yyyy-MM-dd).
    var dayKey: String

    /// - Parameter effortScale: the user's Effort display scale; the figures are shown on it.
    @MainActor
    static func make(days: [DailyMetric], now: Date = Date(), effortScale: EffortScale) -> EffortTargetReading {
        let logicalKey = BodyVitalSigns.logicalDayKey(now)
        let localKey = Repository.localDayKey(now)
        let today = Repository.resolveToday(days: days, logicalKey: logicalKey, localKey: localKey)
        let recovery = Repository.widgetAnchor(days: days, logicalKey: logicalKey, localKey: localKey)?.recovery
        let band = CoupledView.optimalStrainRange(recovery: recovery)
            .map { EffortTarget.Band(whoopLow: $0.lowerBound, whoopHigh: $0.upperBound) }
        let factor = effortScale == .whoop ? UnitFormatter.effortScaleFactor : 1
        let dayKey = today?.day ?? logicalKey

        // Load through the last COMPLETE day: today's Effort is still being earned, and counting a half-day
        // as a finished one would drag the acute load down every morning.
        let loads = days.filter { $0.day < dayKey }
            .map { TrainingLoadEngine.DailyLoad(day: $0.day, load: $0.strain) }
        let load = TrainingLoadEngine.evaluate(days: loads)

        return EffortTargetReading(
            progress: EffortTarget.progress(effort: today?.strain, band: band, displayFactor: factor),
            training: EffortTarget.trainingState(recovery: recovery, load: load),
            recovery: recovery,
            dayKey: dayKey)
    }

    /// Fingerprint of what the reading depends on, so the card recomputes when a day row changes and not
    /// on every unrelated repository publish.
    static func inputKey(days: [DailyMetric], effortScaleRaw: String) -> String {
        "\(effortScaleRaw)|" + TrainingLoadCard.modelKey(for: days)
            + "|\(days.last?.recovery ?? -1)|\(days.last?.strain ?? -1)"
    }

    /// The "How it works" sections. Thresholds are printed from the constants, so the copy cannot drift.
    static var infoSections: [PlannerInfoSection] {
        func ratio(_ v: Double) -> String { String(format: "%.2f", v) }
        return [
            PlannerInfoSection(
                heading: String(localized: "Your target"),
                body: String(localized: "The band is the OPTIMAL range NOOP already shows from your Charge: a higher Charge earns a higher band, a low Charge a lower one. It is shown on the Effort scale you chose, and it uses your last scored Charge until today's is in. It is a guide, not a score, and nothing is fed back into Charge, Effort or Rest.")),
            PlannerInfoSection(
                heading: String(localized: "To go"),
                body: String(localized: "\"13–28 to go\" means that much more Effort takes you from today's figure to the bottom and to the top of the band. Inside the band it says so; above it, by how much. The figures are compared as shown, so they always add up.")),
            PlannerInfoSection(
                heading: String(localized: "Training state"),
                body: String(localized: "One word from today's Charge and your recent load. Recent load is the training-load model's acute figure (7-day time constant) over its chronic one (42-day time constant), through yesterday, on your daily Effort. Ratio \(ratio(EffortTarget.loadHighRatio)) or more is well above your usual; \(ratio(EffortTarget.loadRisingRatio)) or more is rising; under \(ratio(EffortTarget.loadLightRatio)) is light.\n\nRestoring: light load or a low Charge. Balanced: load near your usual with a Charge that supports it. Building: load rising and a high Charge keeping up. Overreaching: load well above your usual and a Charge that is not high.")),
            PlannerInfoSection(
                heading: String(localized: "Calibration"),
                body: String(localized: "The word needs \(TrainingLoadEngine.Configuration.standard.minimumDays) consecutive days of Effort. It is marked as calibrating until \(TrainingLoadEngine.Configuration.standard.establishedDays) days, when the long-term baseline is full.")),
        ]
    }
}

// MARK: - Band bar

/// A thin bar: the target band as a quiet block, Effort filling from the left. Neutral on purpose, so
/// "above the band" never reads as an error.
struct EffortTargetBar: View {
    let progress: EffortTarget.Progress

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.hairline)
                if let lo = progress.lowFraction, let hi = progress.highFraction {
                    Capsule()
                        .fill(StrandPalette.textTertiary.opacity(0.35))
                        .frame(width: max(6, w * CGFloat(hi - lo)))
                        .offset(x: w * CGFloat(lo))
                }
                if let e = progress.effortFraction {
                    Capsule()
                        .fill(StrandPalette.effortColor.opacity(0.85))
                        .frame(width: max(6, w * CGFloat(e)))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Training State label

struct TrainingStateLine: View {
    let reading: EffortTargetReading

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("TRAINING STATE").font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textTertiary)
            if let state = reading.training.state {
                Text(verbatim: state.label)
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(StrandPalette.hairline))
                    .accessibilityIdentifier("effort-target-state")
            }
            Spacer(minLength: 0)
        }
        if let note = note {
            Text(verbatim: note)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("effort-target-calibration")
        }
    }

    /// Why there is no word, or that the word is still settling.
    private var note: String? {
        if let note = reading.training.calibration.note { return note }
        if reading.training.state == nil { return "Appears once today's Charge is scored" }
        return nil
    }
}

// MARK: - Today card

struct EffortTargetCard: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var reading: EffortTargetReading?

    private var key: String { EffortTargetReading.inputKey(days: repo.days, effortScaleRaw: effortScaleRaw) }

    var body: some View {
        NoopCard(tint: StrandPalette.effortColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("EFFORT TARGET").font(StrandFont.overlineScaled(11)).tracking(1.0)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    PlannerInfoButton(title: "Effort target", tint: StrandPalette.effortColor,
                                      sections: EffortTargetReading.infoSections,
                                      calibration: reading?.training.calibration.note,
                                      identifier: "effort-target-info")
                }
                if let reading {
                    Text(verbatim: reading.progress.text)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("effort-target-text")
                    EffortTargetBar(progress: reading.progress)
                    TrainingStateLine(reading: reading)
                } else {
                    Text("Reading your day").font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .containerIdentifier("effort-target-card")
        .onAppear { refresh() }
        .onChangeCompat(of: key) { _ in refresh() }
    }

    @MainActor private func refresh() {
        #if DEBUG
        if let fixture = PlannerFixture.effortReading { reading = fixture; return }
        #endif
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        reading = EffortTargetReading.make(days: repo.days, effortScale: scale)
    }
}

// MARK: - Strain-card line

/// The same sentence and Training State under the Coupled view's Day Strain card.
struct EffortTargetInline: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var reading: EffortTargetReading?

    private var key: String { EffortTargetReading.inputKey(days: repo.days, effortScaleRaw: effortScaleRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reading {
                Divider().overlay(StrandPalette.hairline)
                Text(verbatim: reading.progress.text)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                TrainingStateLine(reading: reading)
            }
        }
        .onAppear { refresh() }
        .onChangeCompat(of: key) { _ in refresh() }
    }

    @MainActor private func refresh() {
        #if DEBUG
        if let fixture = PlannerFixture.effortReading { reading = fixture; return }
        #endif
        let scale = UnitPrefs.resolveEffortScale(effortScaleRaw)
        reading = EffortTargetReading.make(days: repo.days, effortScale: scale)
    }
}
