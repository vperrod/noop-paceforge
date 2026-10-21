#if os(iOS)
import SwiftUI
import StrandDesign

// NOOP Today's PaceForge ring group: Recovery, Sleep and Strain from Garmin data, under the NOOP hero rings, the iPhone twin of the
// web Overview's second ring group. NOOP's and PaceForge's scores are two calculations and are never merged or averaged.
//
// Built small on purpose (builds 465 to 478): every part is its own small view, there is no GeometryReader, ViewThatFits or
// preference key, and PFBuilder is never called from here. The numbers are read from the documents the PaceForge refresh saved on the
// phone (`data/fitness.json` for the day's Garmin figures, `data/readiness-explained.json` for the labelled recovery and sleep
// scores), parsed off the main actor into a tiny Equatable value. Read-only: nothing here writes to the server.

// MARK: - Data

struct PFScoresValues: Equatable {
    var recovery: Double?
    var sleep: Double?
    /// "PaceForge score · 6h14 · 78% of need"
    var sleepLine: String?
    var garminSleep: Double?
    var strain: Double?
    var strainLow: Double?
    var strainHigh: Double?
    /// The sheet behind "Why they differ".
    var why: PFExplainer
    /// One line saying why there is nothing to show; nil while at least one score is there.
    var reason: String?

    var hasAny: Bool { recovery != nil || sleep != nil || strain != nil }
}

/// The saved documents a load reads. Plain bytes, so they cross to the parsing task.
struct PFScoresDocs: Sendable {
    var fitness: Data?
    var readiness: Data?
    var explainers: Data?

    /// The phone's saved copies (a fixture has none).
    static func saved() -> PFScoresDocs {
        guard PFAPI.usesPhoneState else { return PFScoresDocs() }
        return PFScoresDocs(fitness: PFStore.read(path: PFDocs.fitness), readiness: PFStore.read(path: PFDocs.readiness),
                            explainers: PFStore.read(path: PFDocs.explainers))
    }
}

enum PFScoresParse {
    static func values(_ docs: PFScoresDocs, today: String, isSetUp: Bool) -> PFScoresValues {
        let why = whyExplainer(docs.explainers)
        guard isSetUp else { return PFScoresValues(why: why, reason: "PaceForge is not set up on this phone.") }
        guard docs.fitness != nil || docs.readiness != nil else {
            return PFScoresValues(why: why, reason: "PaceForge has not been refreshed on this phone yet.")
        }
        let fitness = PFJ(data: docs.fitness)
        let daily = fitness["daily"]
        let fitnessDay = daily["date"].text ?? fitness["date"].text
        // A document with no date is read as the builder reads it; one written for another day is not today's.
        let fitnessIsToday = docs.fitness != nil && (fitnessDay.map { String($0.prefix(10)) == today } ?? true)
        let readings = DayReadingsParse.document(PFJ(data: docs.readiness))
        let readingsAreToday = readings?.hasLabelled == true && readings?.date == today

        var out = PFScoresValues(why: why)
        out.recovery = (readingsAreToday ? readings?.paceforgeRecovery : nil)
            ?? (fitnessIsToday ? number(daily["recovery"]["score"]) : nil)
        let sleepNode = daily["sleep"]
        out.sleep = (readingsAreToday ? readings?.paceforgeSleepScore : nil)
            ?? (fitnessIsToday ? number(sleepNode["score"]) : nil)
        out.garminSleep = (readingsAreToday ? readings?.garminSleepScore : nil)
            ?? (fitnessIsToday ? number(sleepNode["garmin_score"]) : nil)
        if fitnessIsToday {
            out.sleepLine = sleepLine(sleepNode)
            let strain = daily["strain"]
            if strain["available"].bool != false, let value = number(strain["value"]) {
                out.strain = value
                out.strainLow = number(strain["target_low"])
                out.strainHigh = number(strain["target_high"])
            }
        }
        if !out.hasAny {
            let day = fitnessDay ?? readings?.date
            if let day, String(day.prefix(10)) != today {
                out.reason = "Not refreshed today: the last PaceForge scores are from \(PFFormat.shortDate(day))."
            } else {
                out.reason = "PaceForge has no scores for today yet."
            }
        }
        return out
    }

    private static func number(_ j: PFJ) -> Double? {
        guard let value = j.double, value.isFinite else { return nil }
        return value
    }

    private static func sleepLine(_ sleep: PFJ) -> String? {
        guard let hours = sleep["hours_text"].text else { return nil }
        var parts = ["PaceForge score", hours]
        if let pct = number(sleep["sufficiency_pct"]) { parts.append("\(Safe.int(pct))% of need") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The server's "three scores" explainer when it was saved, else a short one of the app's own.
    private static func whyExplainer(_ data: Data?) -> PFExplainer {
        if let saved = PFWave2Parse.explainers(PFJ(data: data)).first(where: { $0.id == PFExplainerID.readinessSources }) {
            return saved
        }
        return PFExplainer(
            id: PFExplainerID.readinessSources, title: "Why the scores differ",
            plain: "NOOP and PaceForge are two different calculations of the same day, so they can disagree. They are shown next to each other and never averaged or used to fill each other's gaps.",
            how: "Charge, Effort and Rest run 0 to 100 and come from the strap. Recovery and the sleep score are PaceForge's own calculation from Garmin's HRV, resting heart rate and sleep. Strain runs 0 to 21.",
            caveat: "Garmin's own training readiness and sleep score are a third and fourth number. Day > Recovery and Day > Sleep show every source side by side.")
    }
}

// MARK: - Store

@MainActor
final class PFScoresStore: ObservableObject {
    static let shared = PFScoresStore()

    /// nil until the first load has finished; a screen shows nothing before that.
    @Published private(set) var values: PFScoresValues?

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    func refreshIfStale() async {
        if let lastFetch, values != nil, Date().timeIntervalSince(lastFetch) < 120 { return }
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
        guard PFAPI.isConfigured else {
            publish(await Self.parse(PFScoresDocs(), isSetUp: false))
            return
        }
        // The copy on the phone first (read off the main actor), so the card has its numbers while the network answers.
        if values == nil, PFAPI.usesPhoneState { publish(await Self.parse(nil, isSetUp: true)) }
        var fetched: PFScoresDocs?
        var usedBeta = false
        if PFBeta.isOn { usedBeta = await refreshViaCoordinator() }
        if !usedBeta { fetched = await Self.fetchDocuments() }
        // nil: the coordinator saved the documents on the phone, so they are read from there.
        publish(await Self.parse(fetched, isSetUp: true))
        lastFetch = Date()
    }

    private func publish(_ new: PFScoresValues) {
        // NOOP Today observes nothing here; only the card does, and an equal assignment would still redraw it.
        if values != new { values = new }
    }

    /// Beta only (see PaceForgeBeta.swift): the coordinator downloads the documents whose hash changed and saves them. False after a
    /// `refresh.beta.fallback` breadcrumb: the caller then fetches the way build 477 did.
    private func refreshViaCoordinator() async -> Bool {
        do {
            _ = try await PFRefreshCoordinator.shared.refreshIfStale(.snapshot, maxAge: 120)
            return true
        } catch {
            PFBeta.fallback(PFBeta.reason(error))
            return false
        }
    }

    /// The 477 path: the two small documents, from the server, each falling back to the saved copy when the request fails.
    nonisolated private static func fetchDocuments() async -> PFScoresDocs {
        async let fitness = PFAPI.fetchOptional(PFDocs.fitness)
        async let readiness = PFAPI.fetchOptional(PFDocs.readiness)
        let (fresh, readings) = await (fitness, readiness)
        let saved = PFScoresDocs.saved()
        return PFScoresDocs(fitness: fresh ?? saved.fitness, readiness: readings ?? saved.readiness, explainers: saved.explainers)
    }

    /// Parses off the main actor. `nil` documents: the phone's saved copies, read there too.
    private static func parse(_ docs: PFScoresDocs?, isSetUp: Bool) async -> PFScoresValues {
        let today = PFAPI.todayISO
        return await Task.detached(priority: .userInitiated) {
            PFScoresParse.values(docs ?? PFScoresDocs.saved(), today: today, isSetUp: isSetUp)
        }.value
    }
}

// MARK: - Views

private enum PFScoresStyle {
    /// The same size as the NOOP hero rings above (HeroScoreCell.vesselDiameter on iPhone).
    static let diameter: CGFloat = 92
    static var paceforge: Color { PFColor.sky }
    static var garmin: Color { PFColor.positive }
}

/// The card on NOOP Today. Draws nothing until the store has loaded once.
struct PaceForgeScoresGroup: View {
    @ObservedObject private var store = PFScoresStore.shared

    private var crumbKey: Int {
        guard let values = store.values else { return 0 }
        return 8 + (values.recovery != nil ? 1 : 0) + (values.sleep != nil ? 2 : 0) + (values.strain != nil ? 4 : 0)
    }

    // A stack, not a bare `if`: an empty view never runs its own .task or .onAppear, and the load must start before there is a card.
    var body: some View {
        VStack(spacing: 0) {
            if let values = store.values {
                PaceForgeScoresCard(values: values)
            }
        }
        .task { await store.refreshIfStale() }
        .onAppear { crumb() }
        .onChangeCompat(of: crumbKey) { _ in crumb() }
    }

    private func crumb() {
        let values = store.values
        NoopDiag.crumb("today.pfrings recovery=\(values?.recovery != nil) sleep=\(values?.sleep != nil) strain=\(values?.strain != nil)")
    }
}

private struct PaceForgeScoresCard: View {
    let values: PFScoresValues

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaceForgeScoresHeader()
            if let reason = values.reason {
                PaceForgeScoresReason(text: reason)
            }
            PaceForgeScoresRings(values: values)
            PaceForgeScoresFooter(why: values.why)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-scores-group")
    }
}

private struct PaceForgeScoresHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            PaceForgeSourceChip(text: "PaceForge", color: PFScoresStyle.paceforge)
            Text("Calculated from Garmin data")
                .lookCaps(10.5)
                .foregroundStyle(NoopLook.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct PaceForgeSourceChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .lookCaps(10.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(color.opacity(0.16)))
    }
}

private struct PaceForgeScoresReason: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LookFont.text(13.5, weight: .medium))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("pf-scores-reason")
    }
}

/// The three dials side by side: Recovery, Sleep, Strain.
private struct PaceForgeScoresRings: View {
    let values: PFScoresValues
    private let hiding = PFHiding()

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            PaceForgeScoreDial(name: "Recovery", fraction: fraction(values.recovery, max: 100),
                               color: values.recovery.map { NoopLook.chargeColor($0) } ?? NoopLook.chargeHigh,
                               valueText: values.recovery.map { String(Safe.int($0)) } ?? "\u{2013}",
                               unitText: values.recovery == nil ? nil : "%", target: nil,
                               sub: values.recovery == nil ? "none yet today" : "PaceForge recovery",
                               garminScore: nil, identifier: "pf-scores-recovery")
            PaceForgeScoreDial(name: "Sleep", fraction: fraction(values.sleep, max: 100), color: NoopLook.rest,
                               valueText: values.sleep.map { String(Safe.int($0)) } ?? "\u{2013}",
                               unitText: values.sleep == nil ? nil : "%", target: nil,
                               sub: values.sleep == nil ? "none yet today" : (values.sleepLine ?? "PaceForge score"),
                               garminScore: hiding.hides(.scores) ? nil : values.garminSleep, identifier: "pf-scores-sleep")
            PaceForgeScoreDial(name: "Strain", fraction: fraction(values.strain, max: 21), color: NoopLook.effort,
                               valueText: values.strain.map { PFFormat.oneDecimal($0) } ?? "\u{2013}",
                               unitText: nil, target: strainTarget, sub: strainSub,
                               garminScore: nil, identifier: "pf-scores-strain")
        }
    }

    private func fraction(_ value: Double?, max: Double) -> Double {
        value.map { LookDial.fraction($0, max: max) } ?? 0
    }

    private var strainTarget: (start: Double, end: Double)? {
        guard values.strain != nil else { return nil }
        return LookDial.targetArc(low: values.strainLow, high: values.strainHigh, max: 21)
    }

    private var strainSub: String {
        guard values.strain != nil else { return "none yet today" }
        guard let low = values.strainLow, let high = values.strainHigh else { return "of 21" }
        return "target \(Safe.int(low, .towardZero))\u{2013}\(Safe.int(high, .towardZero))"
    }
}

/// One dial: the ring, its name, a line under it and, for Sleep, Garmin's own sleep score as a small chip. Under Hide numbers the
/// ring reads "Hidden" like the NOOP hero rings, and the figures in the line under it are replaced.
private struct PaceForgeScoreDial: View {
    let name: String
    let fraction: Double
    let color: Color
    let valueText: String
    let unitText: String?
    let target: (start: Double, end: Double)?
    let sub: String
    let garminScore: Double?
    let identifier: String
    private let hiding = PFHiding()

    var body: some View {
        VStack(spacing: 8) {
            RingDial(fraction: fraction, color: color, valueText: valueText, unitText: unitText, target: target,
                     diameter: PFScoresStyle.diameter, accessibilityName: name)
                .hiddenWhenPrivate(.scores, name: name)
            Text(name)
                .lookCaps(13.5)
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(1)
            Text(hiding.text(sub))
                .font(LookFont.text(12, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let garminScore {
                PaceForgeGarminSleepChip(score: garminScore)
            }
        }
        .frame(maxWidth: .infinity)
        .containerIdentifier(identifier)
    }
}

private struct PaceForgeGarminSleepChip: View {
    let score: Double

    var body: some View {
        HStack(spacing: 5) {
            PaceForgeSourceChip(text: "Garmin", color: PFScoresStyle.garmin)
            Text("sleep score \(Safe.int(score))")
                .font(LookFont.text(12, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-scores-garmin-sleep")
    }
}

/// "Never merged", and the two links: an inline note (About these scores) and the readiness explanation sheet (Why they differ).
private struct PaceForgeScoresFooter: View {
    let why: PFExplainer
    @State private var isAboutOpen = false
    @State private var isWhyOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOOP and PaceForge are two different calculations, never merged.")
                .font(LookFont.text(13, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Button { isAboutOpen.toggle() } label: { InsightLink("About these scores") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf-scores-about-link")
                Button { isWhyOpen = true } label: { InsightLink("Why they differ") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf-scores-why-link")
                Spacer(minLength: 0)
            }
            if isAboutOpen {
                Text("Charge, Effort and Rest run 0 to 100 and come from the strap. Recovery and the sleep score are PaceForge's own calculation from Garmin's HRV, resting heart rate and sleep; Strain runs 0 to 21. Garmin's own training readiness is a different number.")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-scores-about-text")
            }
        }
        .sheet(isPresented: $isWhyOpen) { PFExplainerSheet(explainer: why) }
    }
}
#endif
