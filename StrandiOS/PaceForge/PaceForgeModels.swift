import Foundation

// View models for the PaceForge tab. PaceForgeBuilder fills them from the live JSON the PaceForge
// server serves (`/api/state` and `/data/*`); the screens only read these value types.

struct PFSnapshot {
    var generatedAt: String?
    /// The day the data was built for, as `yyyy-MM-dd` (the phone's today; fixed in UI-test fixtures).
    var todayISO: String = ""
    var today: PFToday
    var coach: PFCoach
    var weeks: [PFWeek]
    var currentWeekIndex: Int = 0
    var insights: PFInsights
    var body: PFBodyDoc?
    var activities: [String: PFActivity] = [:]
    var analyses: [String: PFAnalysisRow] = [:]
    var trimp: [String: Double] = [:]
    var rpe: [String: Double] = [:]
    /// Recent nights of sleep (minutes asleep), oldest first, for the sleep and HRV trend widget.
    var sleepNights: [PFSleepNight] = []
    /// Every field below arrives from a file an older server may not serve; each is absent, not broken.
    var bodyProgress: PFBodyProgress?
    /// Open alerts only, most urgent first.
    var alerts: [PFAlert] = []
    var readiness: PFReadiness?
    /// Wave 2 files; each is nil or empty when the server does not serve it.
    var feel: PFFeelSummary?
    var whatChanged: PFWhatChanged?
    var behaviour: PFBehaviourImpact?
    /// Every metric explainer, in the server's order.
    var explainers: [PFExplainer] = []
    /// Wave 3 files. Each is nil when the server does not serve it; race week is also nil outside race week.
    var raceWeek: PFRaceWeek?
    var simulations: PFHyroxSims?
    var easyMode: PFEasyMode?
    var muscle: PFMuscleCheck?
    var tape: PFTape?
    /// `standing.json` ("Where you stand"); nil when the server does not serve it.
    var standing: PFStanding?
    /// Bike rides from `ride-metrics.json`, newest first; empty when the server does not serve it.
    var rides: [PFRide] = []
    /// The server's `dismissed.json` (cards hidden in PaceForge); united with the ones hidden on this iPhone.
    var dismissed: [PFDismissal] = []
    /// The server's `today-layout.json` (how the web page arranged the Today cards); empty when it serves none.
    var todayLayout = PFTodayLayout()
    /// `state.settings.privacy.hide_body_on_lock_screen` as the server sent it; nil when it sent nothing.
    var serverHidesBody: Bool?

    /// The rides of one day.
    func rides(on date: String) -> [PFRide] { rides.filter { $0.date == date } }

    /// The explainer with this id, if the server has one.
    func explainer(_ id: String) -> PFExplainer? { explainers.first { $0.id == id } }
}

struct PFSleepNight { var date: String; var minutes: Double }

// MARK: Today

struct PFToday {
    var recovery: PFRecovery?
    var strain: PFStrain?
    var sleep: PFSleep?
    var brief: PFDailyBrief?
    var nextRace: PFNextRace?
    var sessions: [PFWorkout] = []
    var hrv: Double?
    /// The 7-night HRV baseline and the normal band around it, in ms.
    var hrvBaselineMs: Double?
    var hrvLowMs: Double?
    var hrvHighMs: Double?
    var restingHr: Double?
    /// Acute : chronic load ratio.
    var acwr: Double?
}

struct PFRecovery { var score: Double; var band: String?; var confidence: String?; var trust: PFTrust? }
struct PFStrain { var value: Double; var targetLow: Double?; var targetHigh: Double?; var band: String? }
struct PFSleep {
    var score: Double
    var hoursText: String?
    var needText: String?
    var sufficiencyPct: Double?
    var debtHours: Double?
}
struct PFNextRace { var name: String; var date: String; var daysOut: Int; var goalTime: String? }

/// The daily coach briefing, with every field the PaceForge web Today card renders.
struct PFDailyBrief {
    var date: String?
    var headline: String
    var notes: [String] = []
    var outlook: [String] = []
    var bodyState: String?
    var training: String?
    var recent: String?
    var focus: [String] = []
    var pulses: [PFPulse] = []
    /// True while the brief was written without everything it wants (last night's sleep, HRV, the scale).
    var partial = false
    /// What the brief is still waiting for, e.g. ["sleep", "HRV"].
    var missing: [String] = []
    /// When the brief was last rewritten after new data arrived.
    var updatedAt: String?
    var updateCount = 0
    /// One plain line on what moved since yesterday, written by the server.
    var changes: String?
}
struct PFPulse { var at: String?; var text: String }

// MARK: Workouts

struct PFWorkout: Identifiable {
    var id: String
    var date: String
    var status: String
    var name: String?
    var kind: String?
    var sport: String?
    var durationMin: Double?
    var distanceKm: Double?
    var targetRpe: Double?
    var userRpe: Double?
    var cadenceTarget: Double?
    var description: String?
    var briefing: PFBriefing?
    var steps: [PFStep] = []
    var exercises: [PFExercise] = []
    var compliance: PFCompliance?
    var completionAnalysis: String?
    var notes: String?
    /// The Garmin activity this session was matched to, if it has been done.
    var activityId: String?

    var hasResults: Bool { (status == "done" || status == "partial") && activityId != nil }
}

struct PFBriefing {
    var purpose: String?; var structure: String?; var feel: String?; var ifWrong: String?
    var cue: String?; var venue: String?; var fuel: String?; var warmup: String?
}

struct PFStep: Identifiable {
    var type: String?
    var description: String?
    var durationSec: Double?
    var distanceM: Double?
    var targetType: String?
    var targetLow: Double?
    var targetHigh: Double?
    var repeatCount: Int?
    var steps: [PFStep] = []

    // Steps have no identity of their own in the source; the view enumerates them.
    var id: String { "\(type ?? "")|\(description ?? "")|\(durationSec ?? 0)|\(distanceM ?? 0)" }
}

struct PFExercise { var name: String; var sets: Double?; var reps: String?; var rpe: Double?; var cue: String? }
struct PFCompliance {
    var status: String?; var ratio: Double?
    var plannedKm: Double?; var actualKm: Double?; var plannedMin: Double?; var actualMin: Double?
}

// MARK: Activities (completed sessions)

struct PFActivity {
    var id: String
    var name: String?
    var type: String?
    var startTime: String?
    var distanceM: Double?
    var durationS: Double?
    var avgHr: Double?
    var maxHr: Double?
    var avgPaceSecPerKm: Double?
    var calories: Double?
    var teAerobic: Double?
    var teAnaerobic: Double?
    var cadence: Double?
    var strideCm: Double?
    var groundContactMs: Double?
    var avgPower: Double?
    var elevationM: Double?
    var hrr1: PFHRR1?
    var heat: PFHeat?

    var isRun: Bool { (type ?? "").lowercased().contains("run") }
    var isBike: Bool {
        let t = (type ?? "").lowercased()
        return t.contains("cycl") || t.contains("bik")
    }
}

struct PFSample { var t: Double; var hr: Double?; var pace: Double?; var cad: Double? }
struct PFSplit {
    var n: Int; var distanceM: Double?; var paceSec: Double?
    var avgHr: Double?; var elevGain: Double?
}
struct PFZone { var zone: Int; var secs: Double; var low: Double? }
struct PFWeather { var tempC: Double?; var desc: String? }

/// `/data/details/<id>.json`: the heart-rate and pace series, per-km splits and heart-rate zones.
struct PFDetail {
    var hrr1: PFHRR1?
    var samples: [PFSample] = []
    var splits: [PFSplit] = []
    var zones: [PFZone] = []
    var weather: PFWeather?
}

/// One row of `/data/analyses/index.json`: the coach's verdict plus the scored insights.
struct PFAnalysisRow {
    var id: String
    var headline: String?
    var strain: Double?
    var strainBand: String?
    var recoveryReason: String?
    var vsTypicalPercentile: Double?
    var vsTypicalLabel: String?
    var vsTypicalReason: String?
    var plannedKm: Double?
    var plannedMin: Double?
    var actualKm: Double?
    var actualMin: Double?
}

// MARK: Coach

struct PFCoach {
    var brief: PFBrief?
    var take: PFTake?
    var weeklyReview: PFWeeklyReview?
    var chat: [PFChatTurn] = []
}
struct PFBrief { var date: String?; var headline: String; var outlook: [String]? }
struct PFTake {
    var headline: String
    var readinessScore: Double?
    var readinessBand: String?
    var limiters: [PFLimiter]?
    var weekActions: [PFWeekAction]?
}
struct PFLimiter { var name: String; var area: String; var evidence: String; var recommendation: String }
struct PFWeekAction { var area: String; var action: String }
struct PFWeeklyReview {
    var week: String
    var period: PFPeriod
    var headline: String
    var limiters: [String]?
    var plannedRuns: Int?
    var completedRuns: Int?
    var qualityDone: Int?
    var sessions: [PFReviewSession]?
    var fatigue: [PFFatigue]?
    var strengthSaid: String?
    var thisWeek: [String]?
}
struct PFPeriod { var start: String; var end: String }
struct PFReviewSession { var date: String; var name: String; var completed: Bool; var quality: Bool; var status: String? }
struct PFFatigue { var kind: String?; var text: String }
struct PFChatTurn: Identifiable {
    var role: String; var text: String; var ts: String
    var id: String { ts + role }
}

// MARK: Week

struct PFWeek: Identifiable {
    var key: String
    var start: String
    var end: String
    var days: [PFDay]
    var phase: String?
    var focus: String?
    var intro: String?
    var targetHours: Double?
    var tally: String?
    var headline: String?
    var plannedHours: Double?
    var id: String { key }
}
struct PFDay: Identifiable {
    var date: String
    var dow: String
    var workouts: [PFWorkout] = []
    var id: String { date }
}

// MARK: Insights

struct PFInsights {
    var ctl: Double; var atl: Double; var tsb: Double
    var formBand: String?
    var history: [PFLoadPoint] = []
    var projection: [PFLoadPoint] = []
    var markers: [PFMarker]?
    var warnings: [PFWarning]?
    var loadSentence: String?
    var races: [PFRace] = []
    var goalPrognosis: PFGoalPrognosis?
    var hyrox: PFHyrox?
}
struct PFLoadPoint: Identifiable {
    var date: String; var ctl: Double; var atl: Double; var tsb: Double
    var id: String { date }
}
struct PFMarker { var date: String; var name: String }
struct PFWarning { var date: String; var text: String }
struct PFRace: Identifiable {
    var name: String; var date: String; var daysOut: Int
    var headline: String; var readiness: String; var taperOk: Bool?
    var id: String { date + name }
}
struct PFGoalPrognosis { var prognosisSec: Double; var goalSec: Double; var verdict: String; var sentence: String? }
struct PFHyrox {
    var predicted: String
    var basis: String?
    var trend: String?
    var sentence: String?
    var stations: [PFStation]?
}
struct PFStation: Identifiable {
    var name: String; var athlete: String; var top3: String; var gapSec: Double
    var id: String { name }
}

// MARK: Body

/// `/data/body.json`: Hume scale readings with the assessment bands, segmental analysis and goals.
struct PFBodyDoc {
    var date: String
    var score: Double?
    var band: String?
    var age: Int?
    var heightCm: Double?
    var assessment: [PFBodyRange] = []
    var latest: [String: Double] = [:]
    var segments: [PFBodySegment] = []
    var series: [PFBodyReading] = []
    var goals: [PFBodyGoal] = []
    var deltas: [String: PFBodyDelta] = [:]
    var metrics: [String: PFBodyMetric] = [:]
    /// Whether the left/right segment figures are an estimate (nil on a server that does not say).
    var segmentalMeta: PFSegmentalMeta?
}
struct PFBodyRange: Identifiable {
    var key: String; var label: String; var unit: String; var value: Double; var dp: Int
    var low: Double; var high: Double; var scaleLo: Double; var scaleHi: Double; var pos: Double
    var status: String
    var id: String { key }
}
struct PFBodySegment: Identifiable {
    var key: String; var name: String
    var weightKg: Double?; var fatKg: Double?; var ffmKg: Double?; var muscleKg: Double?
    var id: String { key }
    var fatPct: Double? {
        guard let w = weightKg, w > 0, let f = fatKg else { return nil }
        return f / w * 100
    }
}
struct PFBodyReading: Identifiable {
    var date: String
    var values: [String: Double]
    var id: String { date }
}
struct PFBodyGoal: Identifiable {
    var metric: String; var label: String; var unit: String
    var target: Double; var current: Double; var remaining: Double?; var progress: Double?
    var dp: Int; var reached: Bool; var targetDate: String?
    var id: String { metric }
}
struct PFBodyDelta { var d7: Double?; var d30: Double?; var d90: Double? }
struct PFBodyMetric { var label: String; var unit: String; var dp: Int; var good: String }

// MARK: Heart-rate recovery

/// First-minute heart-rate recovery of a session. `kind` says what the figure is: `post` (the heart rate
/// fell after the effort stopped), `interval` (a rebound between intervals, compared with the athlete's
/// own intervals), `walking` (a walking cool-down, not scored) or `not_measurable` (too few readings).
/// Older servers sent `post`/`mid` with fewer fields; `mid` decodes as `interval` with `isEstimated`.
struct PFHRR1 {
    /// Beats the heart rate fell in the first minute; nil when it is not measurable.
    var bpm: Int?
    var kind: String
    /// Beats fallen by two minutes.
    var bpm120: Int?
    /// Heart rate at the moment of stopping, and the highest in the last 30 seconds before it.
    var stopBpm: Int?
    var peakBpm: Int?
    /// Heart rate rose after the stop instead of falling.
    var risingAfterStop = false
    /// Population context for the one-minute drop: flag, low, typical or strong. Neutral caption only.
    var contextBand: String?
    var baselineBpm: Double?
    var delta: Double?
    /// The athlete's own band: good, normal, watch or flag.
    var band: String?
    /// The figure came from an older server's `mid` estimate.
    var isEstimated = false

    static let post = "post"
    static let interval = "interval"
    static let walking = "walking"
    static let notMeasurable = "not_measurable"

    /// The first-minute drop is a real recovery figure only for these kinds.
    var isScored: Bool { (kind == Self.post || kind == Self.interval) && bpm != nil }

    /// The personal band, and only where it applies: a scored kind with a personal baseline.
    var personalBand: String? { isScored && baselineBpm != nil ? band : nil }
}

// MARK: Body progress

/// `/data/body-progress.json`: the body goals against the scale's own noise, with fuel, hydration,
/// balance and visceral notes.
struct PFBodyProgress {
    var date: String?
    var latestReadingDate: String?
    var digest: String?
    var goals: [PFProgressGoal] = []
    /// Half-width of the day-to-day scale noise, in the metric's unit.
    var noiseWeightKg: Double?
    var noiseBodyFatPct: Double?
    var noiseBasis: String?
    var dailyLine: String?
    var fuel: PFFuel?
    var hydration: PFHydration?
    var balance: PFBalance?
    var visceral: PFVisceral?
    var analysis: PFProgressAnalysis?
}

struct PFProgressGoal: Identifiable {
    var metric: String
    var label: String
    var unit: String
    var target: Double?
    var targetDate: String?
    var startValue: Double?
    var startDate: String?
    var current7d: Double?
    var lastReading: Double?
    var neededPerWeek: Double?
    var actualPerWeek: Double?
    var eta: String?
    /// on_track, ahead, behind or insufficient_data.
    var status: String
    var aggressive: Bool
    var id: String { metric }
}

struct PFFuel {
    var bmrKcal: Double?
    var trainingDayKcal: Double?
    var trainingDayBasis: String?
    var proteinLow: Double?
    var proteinHigh: Double?
    var proteinBasis: String?
}
struct PFHydration { var waterPct: Double?; var ecwIcwRatio: Double?; var flag: String?; var reason: String?; var ownNormal: String? }
struct PFBalance {
    var armsPct: Double?; var legsPct: Double?; var maxPct: Double?; var flag: String?; var note: String?
    /// The left/right split is our estimate rather than a measurement; nil or false shows no label.
    var estimate: Bool?
    var method: String?
}
struct PFVisceral { var value: Double?; var band: String?; var standardRange: String? }
struct PFProgressAnalysis { var text: String; var generatedAt: String? }

// MARK: Alerts

/// `/data/alerts.json`. The app is read-only: an alert's actions are shown, answered in Telegram.
struct PFAlert: Identifiable {
    var id: String
    var kind: String?
    /// info, watch or act.
    var severity: String
    var createdAt: String?
    var title: String
    var body: String?
    var actions: [PFAlertAction] = []

    var rank: Int { severity == "act" ? 0 : (severity == "watch" ? 1 : 2) }
}
struct PFAlertAction: Identifiable { var id: String; var label: String }

// MARK: Readiness

/// `/data/readiness-explained.json`: PaceForge's, Garmin's and NOOP's own readiness reads, side by side.
/// They are different measures and are never merged into one number.
struct PFReadiness {
    var date: String?
    var sources: [PFReadinessSource] = []
    /// agree, mixed or disagree.
    var agreement: String?
    var coachNote: String?
    /// "Can I train? Can I train hard?", from the same numbers.
    var answers: PFAnswers?
}
struct PFReadinessSource: Identifiable {
    var source: String
    var score: Double?
    var band: String?
    var drivers: [String] = []
    var factors: [PFReadinessFactor] = []
    var recoveryTimeH: Double?
    var hrv: Double?
    var rhr: Double?
    var sleepPerformance: Double?
    var trust: PFTrust?
    var id: String { source }
}
struct PFReadinessFactor: Identifiable {
    var name: String
    var value: String?
    var status: String?
    var id: String { name }
}
