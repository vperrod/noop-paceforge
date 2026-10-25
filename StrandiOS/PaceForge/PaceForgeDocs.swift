import Foundation

// Which documents PaceForge serves and which parts of the app are made from them. Foundation only, so the builder (compiled into
// the macOS unit-test bundle) can name them too.

/// The documents a refresh keeps: the path on the server (also the name of the saved copy) and where its parsed JSON sits in
/// `PFRawBundle`. A document with no `key` is only saved on the phone (My Day reads it from there).
struct PFDocSpec {
    let path: String
    let key: WritableKeyPath<PFRawBundle, PFJ>?
    var isRequired = false
}

enum PFDocs {
    static let state = "api/state"
    static let fitness = "data/fitness.json"
    static let projection = "data/projection.json"
    static let body = "data/body.json"
    static let hyrox = "data/hyrox_analysis.json"
    static let activities = "data/activities.json"
    static let analysesIndex = "data/analyses/index.json"
    static let analysisStatus = "data/analyses/status.json"
    static let bodyProgress = "data/body-progress.json"
    static let alerts = "data/alerts.json"
    static let readiness = "data/readiness-explained.json"
    static let feelSummary = "data/feel-summary.json"
    static let whatChanged = "data/what-changed.json"
    static let explainers = "data/metric-explainers.json"
    static let behaviour = "data/behaviour-impact.json"
    static let raceWeek = "data/race-week.json"
    static let hyroxSims = "data/hyrox-sims.json"
    static let hyroxSimAnalysis = "data/hyrox-sim-analysis.json"
    static let easyMode = "data/easy-mode.json"
    static let muscle = "data/muscle-check.json"
    static let tape = "data/tape.json"
    static let standing = "data/standing.json"
    static let insightsV2 = "data/insights-v2.json"
    static let dailyIntel = "data/daily-intel.json"
    static let rideMetrics = "data/ride-metrics.json"
    static let dismissed = "data/dismissed.json"
    static let todayLayout = "data/today-layout.json"
    static let needsYou = "data/needs-you.json"
    static let workoutMatches = "data/workout-matches.json"
    static let pageNotes = "data/page-notes.json"

    static let all: [PFDocSpec] = [
        PFDocSpec(path: state, key: \PFRawBundle.state, isRequired: true),
        PFDocSpec(path: fitness, key: \PFRawBundle.fitness, isRequired: true),
        PFDocSpec(path: projection, key: \PFRawBundle.projection),
        PFDocSpec(path: body, key: \PFRawBundle.body),
        PFDocSpec(path: hyrox, key: \PFRawBundle.hyrox),
        PFDocSpec(path: activities, key: \PFRawBundle.activities),
        PFDocSpec(path: analysesIndex, key: \PFRawBundle.analysesIndex),
        PFDocSpec(path: analysisStatus, key: \PFRawBundle.analysisStatus),
        PFDocSpec(path: bodyProgress, key: \PFRawBundle.bodyProgress),
        PFDocSpec(path: alerts, key: \PFRawBundle.alerts),
        PFDocSpec(path: readiness, key: \PFRawBundle.readiness),
        PFDocSpec(path: feelSummary, key: \PFRawBundle.feelSummary),
        PFDocSpec(path: whatChanged, key: \PFRawBundle.whatChanged),
        PFDocSpec(path: explainers, key: \PFRawBundle.explainers),
        PFDocSpec(path: behaviour, key: \PFRawBundle.behaviour),
        PFDocSpec(path: raceWeek, key: \PFRawBundle.raceWeek),
        PFDocSpec(path: hyroxSims, key: \PFRawBundle.hyroxSims),
        PFDocSpec(path: hyroxSimAnalysis, key: \PFRawBundle.hyroxSimAnalysis),
        PFDocSpec(path: easyMode, key: \PFRawBundle.easyMode),
        PFDocSpec(path: muscle, key: \PFRawBundle.muscle),
        PFDocSpec(path: tape, key: \PFRawBundle.tape),
        PFDocSpec(path: standing, key: \PFRawBundle.standing),
        PFDocSpec(path: insightsV2, key: \PFRawBundle.insightsV2),
        PFDocSpec(path: dailyIntel, key: \PFRawBundle.dailyIntel),
        PFDocSpec(path: PFDocPath.healthspan, key: \PFRawBundle.healthspan),
        PFDocSpec(path: PFDocPath.journalImpact, key: \PFRawBundle.journalImpact),
        PFDocSpec(path: PFDocPath.highlights, key: \PFRawBundle.highlights),
        PFDocSpec(path: PFDocPath.monthlyReport, key: \PFRawBundle.monthlyReport),
        PFDocSpec(path: PFDocPath.myPlan, key: \PFRawBundle.myPlan),
        PFDocSpec(path: rideMetrics, key: \PFRawBundle.rideMetrics),
        PFDocSpec(path: dismissed, key: \PFRawBundle.dismissed),
        PFDocSpec(path: todayLayout, key: \PFRawBundle.todayLayout),
        PFDocSpec(path: needsYou, key: \PFRawBundle.needsYou),
        // Not part of the bundle's view models: fetched so My Day finds it saved on the phone (PFStore).
        PFDocSpec(path: workoutMatches, key: \PFRawBundle.workoutMatches),
        // No key: the notes are read from the saved copy by PFPageNotesStore, so a change never rebuilds the snapshot.
        PFDocSpec(path: pageNotes, key: nil),
    ]

    /// The documents the widget summary and the reminders are made from: everything except the ones they never read. A document
    /// added later counts as read until it is listed here, so a missed entry costs a widget reload, never a stale widget.
    static let summaryInputs: Set<String> = Set(all.map { $0.path }).subtracting(
        [analysesIndex, analysisStatus, bodyProgress, whatChanged, explainers, behaviour, hyroxSims, hyroxSimAnalysis, easyMode, muscle, tape,
         dailyIntel, dismissed, todayLayout, needsYou, workoutMatches, pageNotes] + PFDocPath.all)

    static func specs(for scope: PFRefreshScope) -> [PFDocSpec] {
        if scope.contains(.snapshot) { return all }
        var out: [PFDocSpec] = []
        if scope.contains(.dailyIntel) { out += all.filter { $0.path == dailyIntel } }
        if scope.contains(.phase4) { out += all.filter { PFDocPath.all.contains($0.path) } }
        return out
    }
}

/// What a refresh covers: the snapshot (every document), or only the documents one shared store shows.
struct PFRefreshScope: OptionSet, Hashable {
    let rawValue: Int
    static let dailyIntel = PFRefreshScope(rawValue: 1)
    static let phase4 = PFRefreshScope(rawValue: 2)
    static let snapshot = PFRefreshScope(rawValue: 4)
    static let everything: PFRefreshScope = [.dailyIntel, .phase4, .snapshot]
    static let parts: [PFRefreshScope] = [.dailyIntel, .phase4, .snapshot]
}
