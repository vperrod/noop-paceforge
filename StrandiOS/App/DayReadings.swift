#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Day > Sleep and Day > Recovery: the same morning as each source reports it, side by side
//
// The iPhone twin of the web's "Last night, three readings" and "Readiness, three readings". Every number names whose it is
// (NOOP blue, PaceForge and Garmin orange) and two values for one question sit next to each other, never averaged or used to fill
// each other's gaps. The numbers come from the `labelled` block of `data/readiness-explained.json`, read from the copy the PaceForge
// refresh already saved on the phone (PFStore): this file fetches nothing and builds nothing. A source with no value is an empty
// reading that says why.

// MARK: Data

struct DayReadings: Equatable, Sendable {
    struct Factor: Equatable, Sendable {
        var name: String
        var value: String?
        var status: String?
    }

    var date: String?
    /// False for a document written by a server that does not send the `labelled` block.
    var hasLabelled = false
    var agreement: String?
    var coachNote: String?

    // Last night
    var paceforgeSleepScore: Double?
    var garminSleepScore: Double?
    var noopSleepPerformance: Double?
    var garminSleepFactor: Double?
    var garminSleepFactorStatus: String?
    var sleepScoreUsed: String?
    var lastNightNeedText: String?
    var tonightNeedText: String?
    var tonightBedtime: String?

    // This morning's readiness
    var noopCharge: Double?
    var paceforgeRecovery: Double?
    var paceforgeBand: String?
    var garminReadiness: Double?
    var garminLevel: String?
    var readinessUsed: String?
    var paceforgeDrivers: [String] = []
    var garminFactors: [Factor] = []
    var garminRecoveryTimeH: Double?
    var noopHrv: Double?
    var noopRhr: Double?
    var noopSleepPerformanceInput: Double?
}

enum DayReadingsParse {
    static func document(_ j: PFJ) -> DayReadings? {
        guard j.exists, j.raw is [String: Any] else { return nil }
        var out = DayReadings()
        out.date = j["date"].text
        out.agreement = j["agreement"].text
        out.coachNote = j["coach_note"].text
        let labelled = j["labelled"]
        out.hasLabelled = labelled.exists
        guard labelled.exists else { return out }
        parseSleep(labelled, into: &out)
        parseReadiness(labelled, into: &out)
        parseSources(j["sources"], into: &out)
        return out
    }

    private static func parseSleep(_ labelled: PFJ, into out: inout DayReadings) {
        let score = labelled["sleep_score"]
        out.paceforgeSleepScore = number(score["paceforge_sleep_score"])
        out.garminSleepScore = number(score["garmin_sleep_score"])
        out.noopSleepPerformance = number(score["noop_sleep_performance"])
        out.garminSleepFactor = number(score["garmin_readiness_sleep_factor"])
        out.sleepScoreUsed = labelled["sleep_score_used_in_the_brief"].text
        let need = labelled["sleep_need"]
        out.lastNightNeedText = need["last_night_need_text"].text
        out.tonightNeedText = need["tonight_need_text"].text
        out.tonightBedtime = need["tonight_bedtime"].text
    }

    private static func parseReadiness(_ labelled: PFJ, into out: inout DayReadings) {
        let readiness = labelled["readiness"]
        out.noopCharge = number(readiness["noop_charge"]["score"])
        out.paceforgeRecovery = number(readiness["paceforge_recovery"]["score"])
        out.paceforgeBand = readiness["paceforge_recovery"]["band"].text
        out.garminReadiness = number(readiness["garmin_training_readiness"]["score"])
        out.garminLevel = readiness["garmin_training_readiness"]["level"].text
        out.readinessUsed = labelled["readiness_used_for_the_call"].text
    }

    private static func parseSources(_ list: PFJ, into out: inout DayReadings) {
        func source(_ name: String) -> PFJ { list.array.first { $0["source"].string == name } ?? PFJ(nil) }
        out.paceforgeDrivers = source("PaceForge")["drivers"].array.compactMap { $0.text }
        let garmin = source("Garmin")
        out.garminFactors = garmin["factors"].array.compactMap { factor in
            guard let name = factor["name"].text else { return nil }
            return DayReadings.Factor(name: name, value: scalarText(factor["value"]), status: factor["status"].text)
        }
        out.garminRecoveryTimeH = number(garmin["recovery_time_h"])
        if let sleepFactor = out.garminFactors.first(where: { $0.name == "last night's sleep" }) {
            out.garminSleepFactorStatus = sleepFactor.status
        }
        let noop = source("NOOP")
        out.noopHrv = number(noop["hrv"])
        out.noopRhr = number(noop["rhr"])
        out.noopSleepPerformanceInput = number(noop["sleep_performance"])
    }

    private static func number(_ j: PFJ) -> Double? {
        guard let value = j.double, value.isFinite else { return nil }
        return value
    }

    private static func scalarText(_ j: PFJ) -> String? {
        j.text ?? number(j).map { PFFormat.trimmed($0) }
    }
}

/// What a reading card shows: a notice that says why there is nothing to compare, or the readings.
struct DayReadingsState {
    var notice: String?
    var readings: DayReadings?
}

@MainActor
final class DayReadingsStore: ObservableObject {
    static let shared = DayReadingsStore()

    @Published private(set) var readings: DayReadings?
    @Published private(set) var didLoad = false

    /// Reads the saved copy of the document off the main thread. Nothing is fetched.
    func load() async {
        let parsed = await Task.detached(priority: .userInitiated) { () -> DayReadings? in
            DayReadingsParse.document(PFJ(data: PFStore.read(path: PFDocs.readiness)))
        }.value
        if readings != parsed { readings = parsed }
        if !didLoad { didLoad = true }
    }

    var state: DayReadingsState {
        guard didLoad else {
            return DayReadingsState(notice: "Reading the PaceForge numbers saved on this phone.")
        }
        guard let readings else {
            return DayReadingsState(notice: "The readings file is not on this phone yet. Open the PaceForge tab once and it is fetched. NOOP's own numbers are below.")
        }
        guard readings.hasLabelled else {
            return DayReadingsState(notice: "This PaceForge server does not send the labelled readings yet, so nothing is compared. NOOP's own numbers are below.")
        }
        guard readings.date == PFAPI.todayISO else {
            let day = readings.date ?? "an earlier day"
            return DayReadingsState(notice: "The comparison between sources is kept for the latest morning (\(day)). Today shows NOOP's own numbers below. Nothing is carried over from another day.")
        }
        return DayReadingsState(readings: readings)
    }
}

// MARK: Source chips and one reading

private enum ReadingSource {
    case noop, paceforge, garmin

    var name: String {
        switch self {
        case .noop: return "NOOP"
        case .paceforge: return "PaceForge"
        case .garmin: return "Garmin"
        }
    }

    var color: Color {
        switch self {
        case .noop: return Color(hex: "#5B9BFF")
        case .paceforge: return Color(hex: "#FF9F3D")
        case .garmin: return Color(hex: "#F08A24")
        }
    }
}

private enum ReadingBand {
    /// green, amber, red from PaceForge's band words ("yellow" is amber).
    static func color(band: String?) -> Color? {
        switch band?.lowercased() {
        case "green": return PFColor.positive
        case "amber", "yellow": return PFColor.warning
        case "red": return PFColor.critical
        default: return nil
        }
    }

    /// Garmin's training readiness level.
    static func color(garminLevel: String?) -> Color? {
        switch garminLevel?.uppercased() {
        case "PRIME", "HIGH": return PFColor.positive
        case "MODERATE": return PFColor.warning
        case "LOW", "POOR": return PFColor.critical
        default: return nil
        }
    }

    /// Garmin's factor status, for the colour only; the word is printed as Garmin gave it.
    static func color(factorStatus: String?) -> Color? {
        switch factorStatus?.uppercased() {
        case "VERY_GOOD", "GOOD": return PFColor.positive
        case "MODERATE": return PFColor.warning
        case "LOW", "POOR": return PFColor.critical
        default: return nil
        }
    }

    static func words(_ raw: String?) -> String? {
        raw?.lowercased().replacingOccurrences(of: "_", with: " ")
    }
}

private func readingInt(_ value: Double?) -> Int? {
    value.map { Safe.int($0) }
}

private struct ReadingSourceChip: View {
    let source: ReadingSource

    var body: some View {
        Text(source.name)
            .lookCaps(10.5)
            .foregroundStyle(source.color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(source.color.opacity(0.16)))
    }
}

private struct ReadingMini: View {
    let key: String
    let label: String
    let value: String?
    let unit: String
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(hiding.shown(value ?? "\u{2013}", .scores))
                    .font(StrandFont.rounded(20))
                    .foregroundStyle(StrandPalette.textPrimary)
                if value != nil, !hiding.hides(.scores) {
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("day-reading-mini-\(key)")
    }
}

/// One reading: whose it is, what it is, the number (or why there is none), what it means and what drives it.
private struct ReadingCell: View {
    let key: String
    let source: ReadingSource
    let name: String
    let value: Int?
    let unit: String
    var color: Color?
    var bandText: String?
    var tag: String?
    let meaning: String
    let why: String
    var drivers: [String] = []
    var minis: [ReadingMiniData] = []
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            top
            valueRow
            Text(meaning)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            miniRow
            driverList
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
        .containerIdentifier("day-reading-\(key)")
    }

    private var top: some View {
        HStack(spacing: 8) {
            ReadingSourceChip(source: source)
            Text(name)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let tag {
                Text(tag).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var valueRow: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hiding.shown(String(value), .scores))
                    .font(StrandFont.rounded(30))
                    .foregroundStyle(hiding.hides(.scores) ? StrandPalette.textTertiary : (color ?? StrandPalette.textPrimary))
                    .accessibilityIdentifier("day-reading-value-\(key)")
                if !hiding.hides(.scores) {
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    if let bandText { PFChip(text: bandText, color: color ?? StrandPalette.textSecondary) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("\u{2013}").font(StrandFont.rounded(30)).foregroundStyle(StrandPalette.textTertiary)
                Text(why)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("day-reading-none-\(key)")
        }
    }

    @ViewBuilder private var miniRow: some View {
        if !minis.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                ForEach(minis) { ReadingMini(key: $0.id, label: $0.label, value: $0.value, unit: $0.unit) }
            }
        }
    }

    @ViewBuilder private var driverList: some View {
        if !drivers.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(drivers.prefix(6).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ReadingMiniData: Identifiable {
    let id: String
    let label: String
    let value: String?
    let unit: String
}

// MARK: Card frame and notices

private struct ReadingsFrame<Content: View>: View {
    let title: String
    let identifier: String
    let subtitle: String?
    let agreement: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                subtitleRow
                content()
            }
        }
        .containerIdentifier(identifier)
    }

    @ViewBuilder private var subtitleRow: some View {
        if subtitle != nil || agreement != nil {
            HStack(spacing: 8) {
                if let subtitle {
                    Text(subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                if let agreement {
                    PFChip(text: agreement, color: Self.agreementColor(agreement))
                        .accessibilityIdentifier("day-reading-agreement")
                }
            }
        }
    }

    private static func agreementColor(_ text: String) -> Color {
        switch text {
        case "Agree": return PFColor.positive
        case "Disagree": return PFColor.critical
        default: return PFColor.warning
        }
    }
}

private struct ReadingsNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("day-readings-notice")
    }
}

private struct ReadingsWhy: View {
    let text: String

    var body: some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("day-readings-why")
    }
}

// MARK: Day > Sleep

struct SleepThreeReadings: View {
    @ObservedObject private var store = DayReadingsStore.shared

    var body: some View {
        let state = store.state
        ReadingsFrame(title: "Last night, three readings", identifier: "day-sleep-three-readings",
                      subtitle: state.readings?.date.map { "Morning of \($0). Each number names whose it is." },
                      agreement: nil) {
            SleepReadingsContent(state: state)
        }
        .task { await store.load() }
    }
}

private struct SleepReadingsContent: View {
    let state: DayReadingsState

    var body: some View {
        if let notice = state.notice {
            ReadingsNotice(text: notice)
        } else if let readings = state.readings {
            SleepReadingsReady(readings: readings)
        }
    }
}

private struct SleepReadingsReady: View {
    let readings: DayReadings

    private var why: String {
        let scores = [readings.paceforgeSleepScore, readings.garminSleepScore, readings.noopSleepPerformance]
            .compactMap { readingInt($0) }
        var spread = ""
        if scores.count > 1, let low = scores.min(), let high = scores.max() { spread = "They run from \(low) to \(high). " }
        return spread + "Same night, three calculations: PaceForge weighs hours against your need, consistency, efficiency and sleep stress from Garmin's data; NOOP does its own version from the strap; Garmin's score is its own model. They are never averaged or used to fill each other's gaps."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReadingCell(key: "paceforge_sleep_score", source: .paceforge, name: "PaceForge sleep score",
                        value: readingInt(readings.paceforgeSleepScore), unit: "/100",
                        tag: readings.sleepScoreUsed == "paceforge_sleep_score" ? "quoted in the brief" : nil,
                        meaning: "Calculated from Garmin's sleep data: hours against the sleep you need, consistency, efficiency and sleep stress.",
                        why: "PaceForge has no sleep score for last night: it needs the watch's sleep record, which has not arrived.")
            ReadingCell(key: "garmin_sleep_score", source: .garmin, name: "Garmin sleep score",
                        value: readingInt(readings.garminSleepScore), unit: "/100",
                        tag: readings.sleepScoreUsed == "garmin_sleep_score" ? "quoted in the brief" : nil,
                        meaning: "Garmin's own score for the same night, from its own model.",
                        why: "Garmin has not scored last night: the watch does it after it syncs.")
            ReadingCell(key: "noop_sleep_performance", source: .noop, name: "NOOP sleep performance (Rest)",
                        value: readingInt(readings.noopSleepPerformance), unit: "%",
                        tag: readings.sleepScoreUsed == "noop_sleep_performance" ? "quoted in the brief" : nil,
                        meaning: "The strap's own version, from the night it recorded: how much of the sleep you need it saw. NOOP's Rest ring is this number.",
                        why: "NOOP has no sleep performance for last night: the strap has not synced a scored night.")
            ReadingCell(key: "garmin_readiness_sleep_factor", source: .garmin, name: "Garmin readiness, last night's sleep factor",
                        value: readingInt(readings.garminSleepFactor), unit: "%",
                        color: ReadingBand.color(factorStatus: readings.garminSleepFactorStatus),
                        bandText: ReadingBand.words(readings.garminSleepFactorStatus),
                        meaning: "Not a sleep score: how much last night's sleep is helping Garmin's training readiness this morning.",
                        why: "Garmin's training readiness has no sleep factor this morning.")
            SleepNeedBlock(lastNight: readings.lastNightNeedText, tonight: readings.tonightNeedText,
                           bedtime: readings.tonightBedtime)
            ReadingsWhy(text: why)
        }
    }
}

/// Last night's need (PaceForge) next to tonight's need (NOOP, provisional until today's Effort is in).
private struct SleepNeedBlock: View {
    let lastNight: String?
    let tonight: String?
    let bedtime: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SleepNeedRow(key: "sleep_need_last_night", label: "Last night's need", text: lastNight, source: .paceforge,
                         note: nil, none: "PaceForge has no need for last night: no sleep is on file for it.")
            SleepNeedRow(key: "sleep_need_tonight", label: "Tonight's need", text: tonight, source: .noop,
                         note: bedtime.map { "provisional, bed \($0)" } ?? "provisional",
                         none: "NOOP works tonight's need out once today's Effort is in; it has not yet.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
        .containerIdentifier("day-sleep-needs")
    }
}

private struct SleepNeedRow: View {
    let key: String
    let label: String
    let text: String?
    let source: ReadingSource
    let note: String?
    let none: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                ReadingSourceChip(source: source)
                Spacer(minLength: 0)
                Text(text ?? "\u{2013}")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .accessibilityIdentifier("day-reading-\(key)")
            }
            if text != nil {
                if let note { Text(note).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary) }
            } else {
                Text(none)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Day > Recovery

struct RecoveryThreeReadings: View {
    @ObservedObject private var store = DayReadingsStore.shared
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        let state = store.state
        ReadingsFrame(title: "Readiness, three readings", identifier: "day-recovery-three-readings",
                      subtitle: state.readings?.date.map { "Morning of \($0). Each number names whose it is." },
                      agreement: Self.agreementWord(state.readings?.agreement)) {
            RecoveryReadingsContent(state: state, noop: noop)
        }
        .task { await store.load() }
    }

    /// NOOP's own numbers for today, from the phone's own store (not from PaceForge's copy of them).
    private var noop: NoopTodayReadings {
        let today = repo.today
        let effort = today?.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) }
        return NoopTodayReadings(charge: today?.recovery, effortText: effort,
                                 effortUnit: "/\(UnitFormatter.effortScaleMax(effortScale))")
    }

    private static func agreementWord(_ raw: String?) -> String? {
        switch raw {
        case "agree": return "Agree"
        case "mixed": return "Mixed"
        case "disagree": return "Disagree"
        default: return nil
        }
    }
}

private struct NoopTodayReadings {
    var charge: Double?
    var effortText: String?
    var effortUnit: String
}

private struct RecoveryReadingsContent: View {
    let state: DayReadingsState
    let noop: NoopTodayReadings

    var body: some View {
        if let notice = state.notice {
            ReadingsNotice(text: notice)
        } else if let readings = state.readings {
            RecoveryReadingsReady(readings: readings, noop: noop)
        }
    }
}

private struct RecoveryReadingsReady: View {
    let readings: DayReadings
    let noop: NoopTodayReadings

    private var charge: Double? { noop.charge ?? readings.noopCharge }

    private var why: String {
        (readings.coachNote ?? "Each score weighs different inputs against its own baseline.") + " They are never averaged."
    }

    private var noopDrivers: [String] {
        var lines: [String] = []
        if let hrv = readings.noopHrv { lines.append("HRV \(PFFormat.trimmed(hrv)) ms") }
        if let rhr = readings.noopRhr { lines.append("Resting HR \(PFFormat.trimmed(rhr)) bpm") }
        if let sleep = readings.noopSleepPerformanceInput { lines.append("Sleep performance \(PFFormat.trimmed(sleep))%") }
        return lines
    }

    private var garminDrivers: [String] {
        var lines = readings.garminFactors.map { factor in
            [factor.name, factor.value.map { "\($0)%" }, ReadingBand.words(factor.status).map { "(\($0))" }]
                .compactMap { $0 }.joined(separator: " ")
        }
        if let hours = readings.garminRecoveryTimeH { lines.append("Recovery time \(PFFormat.trimmed(hours)) h") }
        return lines
    }

    private var noopMinis: [ReadingMiniData] {
        [ReadingMiniData(id: "noop_effort", label: "Effort", value: noop.effortText, unit: noop.effortUnit),
         ReadingMiniData(id: "noop_rest", label: "Rest", value: readingInt(readings.noopSleepPerformance).map { String($0) }, unit: "%")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReadingCell(key: "noop_charge", source: .noop, name: "NOOP Charge", value: readingInt(charge), unit: "/100",
                        color: charge.map { NoopLook.chargeColor($0) },
                        tag: readings.readinessUsed == "noop_charge" ? "used for today's call" : nil,
                        meaning: "The strap's recovery for the day, with its Effort and Rest.",
                        why: "NOOP has not scored Charge for this morning: the strap has not synced a scored night.",
                        drivers: noopDrivers, minis: noopMinis)
            ReadingCell(key: "paceforge_recovery", source: .paceforge, name: "PaceForge recovery",
                        value: readingInt(readings.paceforgeRecovery), unit: "/100",
                        color: ReadingBand.color(band: readings.paceforgeBand), bandText: readings.paceforgeBand?.lowercased(),
                        tag: readings.readinessUsed == "paceforge_recovery" ? "used for today's call" : nil,
                        meaning: "HRV, resting heart rate and sleep against your own baselines, from Garmin data.",
                        why: "PaceForge has no recovery for this morning: it needs last night from the watch.",
                        drivers: readings.paceforgeDrivers)
            ReadingCell(key: "garmin_training_readiness", source: .garmin, name: "Garmin training readiness",
                        value: readingInt(readings.garminReadiness), unit: "/100",
                        color: ReadingBand.color(garminLevel: readings.garminLevel), bandText: readings.garminLevel?.lowercased(),
                        tag: readings.readinessUsed == "garmin_training_readiness" ? "used for today's call" : nil,
                        meaning: "Garmin's score for how ready you are to train: it also weighs load and recovery time.",
                        why: "Garmin has no training readiness for this morning: the watch has not produced one.",
                        drivers: garminDrivers)
            ReadingsWhy(text: why)
        }
    }
}
#endif
