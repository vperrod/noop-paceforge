#if os(iOS)
import SwiftUI
import StrandDesign

// The data behind NOOP Today's PaceForge rings: Recovery, Sleep and Strain from Garmin data, the right half of the six-ring row
// (TodaySixRings.swift). NOOP's and PaceForge's scores are two calculations and are never merged or averaged.
//
// Built small on purpose (builds 465 to 478): there is no GeometryReader, ViewThatFits or preference key, and PFBuilder is
// never called from here. The numbers are read from the documents the PaceForge refresh saved on the
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
        // The copy on the phone first (read off the main actor), so the rings have their numbers while the network answers.
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
        // NOOP Today observes nothing here; only the PaceForge ring group does, and an equal assignment would still redraw it.
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
#endif
