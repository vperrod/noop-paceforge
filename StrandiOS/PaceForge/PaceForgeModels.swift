import Foundation

// Preview snapshot of the PaceForge web screens, bundled as PaceForgePreview.json.
// The live server step replaces `PFSnapshot.load()`; the screens only read these value types.

struct PFSnapshot: Decodable {
    let asOf: String
    let label: String
    let today: PFToday
    let coach: PFCoach
    let weeks: [PFWeek]
    let insights: PFInsights
    let body: PFBody

    static func load() -> Result<PFSnapshot, Error> {
        Result {
            guard let url = Bundle.main.url(forResource: "PaceForgePreview", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(PFSnapshot.self, from: Data(contentsOf: url))
        }
    }
}

// MARK: Today

struct PFToday: Decodable {
    let recovery: PFRecovery
    let strain: PFStrain
    let sleep: PFSleep
    let verdict: PFVerdict
    let briefHeadline: String?
    let nextRace: PFNextRace?
    let sessions: [PFWorkout]?
}

struct PFRecovery: Decodable { let score: Double; let band: String?; let confidence: String?; let reason: String? }
struct PFStrain: Decodable { let value: Double; let targetLow: Double?; let targetHigh: Double?; let band: String?; let reason: String? }
struct PFSleep: Decodable {
    let score: Double; let hoursText: String?; let needText: String?
    let sufficiencyPct: Double?; let debtHours: Double?; let reason: String?
}
struct PFVerdict: Decodable {
    let word: String
    let advice: String?
    let signals: [PFSignal]?
    let garmin: PFGarmin?
}
struct PFSignal: Decodable { let label: String; let flag: String; let evidence: String?; let detail: String? }
struct PFGarmin: Decodable { let status: String?; let hold: Bool?; let reason: String? }
struct PFNextRace: Decodable { let name: String; let date: String; let daysOut: Int; let goalTime: String? }

// MARK: Workouts

struct PFWorkout: Decodable, Identifiable {
    let id: String
    let date: String
    let name: String?
    let kind: String?
    let sport: String?
    let status: String
    let durationMin: Double?
    let distanceKm: Double?
    let targetRpe: Double?
    let userRpe: Double?
    let cadenceTarget: Double?
    let description: String?
    let briefing: PFBriefing?
    let steps: [PFStep]?
    let exercises: [PFExercise]?
    let compliance: PFCompliance?
    let completionAnalysis: String?
    let notes: String?
}

struct PFBriefing: Decodable {
    let purpose: String?; let structure: String?; let feel: String?; let ifWrong: String?
    let cue: String?; let venue: String?; let fuel: String?; let warmup: String?
}

struct PFStep: Decodable, Identifiable {
    let type: String?
    let description: String?
    let durationSec: Double?
    let distanceM: Double?
    let targetType: String?
    let targetLow: Double?
    let targetHigh: Double?
    let repeatCount: Int?
    let steps: [PFStep]?

    // Steps have no identity of their own in the source; the view enumerates them.
    var id: String { "\(type ?? "")|\(description ?? "")|\(durationSec ?? 0)|\(distanceM ?? 0)" }

    private enum CodingKeys: String, CodingKey {
        case type, description, durationSec, distanceM, targetType, targetLow, targetHigh, steps
        case repeatCount = "repeat"
    }
}

struct PFExercise: Decodable { let name: String; let sets: Double?; let reps: String?; let rpe: Double?; let cue: String? }
struct PFCompliance: Decodable {
    let status: String?; let ratio: Double?
    let plannedKm: Double?; let actualKm: Double?; let plannedMin: Double?; let actualMin: Double?
}

// MARK: Coach

struct PFCoach: Decodable {
    let brief: PFBrief
    let take: PFTake
    let weeklyReview: PFWeeklyReview
    let chat: [PFChatTurn]
}
struct PFBrief: Decodable { let date: String?; let headline: String; let outlook: [String]? }
struct PFTake: Decodable {
    let headline: String
    let readinessScore: Double?
    let readinessBand: String?
    let limiters: [PFLimiter]?
    let weekActions: [PFWeekAction]?
}
struct PFLimiter: Decodable { let name: String; let area: String; let evidence: String; let recommendation: String }
struct PFWeekAction: Decodable { let area: String; let action: String }
struct PFWeeklyReview: Decodable {
    let week: String
    let period: PFPeriod
    let headline: String
    let limiters: [String]?
    let plannedRuns: Int?
    let completedRuns: Int?
    let qualityDone: Int?
    let sessions: [PFReviewSession]?
    let fatigue: [PFFatigue]?
    let strengthSaid: String?
    let thisWeek: [String]?
}
struct PFPeriod: Decodable { let start: String; let end: String }
struct PFReviewSession: Decodable { let date: String; let name: String; let completed: Bool; let quality: Bool; let status: String? }
struct PFFatigue: Decodable { let kind: String?; let text: String }
struct PFChatTurn: Decodable, Identifiable {
    let role: String; let text: String; let ts: String
    var id: String { ts + role }
}

// MARK: Week

struct PFWeek: Decodable, Identifiable {
    let key: String
    let start: String
    let end: String
    let phase: String?
    let focus: String?
    let intro: String?
    let targetHours: Double?
    let tally: String?
    let headline: String?
    let plannedHours: Double?
    let days: [PFDay]
    var id: String { key }
}
struct PFDay: Decodable, Identifiable {
    let date: String
    let dow: String
    let workouts: [PFWorkout]?
    var id: String { date }
}

// MARK: Insights

struct PFInsights: Decodable {
    let ctl: Double; let atl: Double; let tsb: Double; let formBand: String?
    let history: [PFLoadPoint]
    let projection: [PFLoadPoint]
    let markers: [PFMarker]?
    let warnings: [PFWarning]?
    let loadSentence: String?
    let races: [PFRace]
    let goalPrognosis: PFGoalPrognosis?
    let hyrox: PFHyrox?
}
struct PFLoadPoint: Decodable, Identifiable {
    let date: String; let ctl: Double; let atl: Double; let tsb: Double
    var id: String { date }
}
struct PFMarker: Decodable { let date: String; let name: String }
struct PFWarning: Decodable { let date: String; let text: String }
struct PFRace: Decodable, Identifiable {
    let name: String; let date: String; let daysOut: Int
    let headline: String; let readiness: String; let taperOk: Bool?
    var id: String { date + name }
}
struct PFGoalPrognosis: Decodable { let prognosisSec: Double; let goalSec: Double; let verdict: String; let sentence: String? }
struct PFHyrox: Decodable {
    let predicted: String; let basis: String?; let trend: String?; let sentence: String?
    let stations: [PFStation]?
}
struct PFStation: Decodable, Identifiable {
    let name: String; let athlete: String; let top3: String; let gapSec: Double
    var id: String { name }
}

// MARK: Body

struct PFBody: Decodable {
    let date: String
    let latest: PFBodyLatest
    let series: [PFBodyPoint]
    let goals: [PFBodyGoal]?
}
struct PFBodyLatest: Decodable {
    let weightKg: Double?; let bodyFatPct: Double?; let muscleMassKg: Double?
    let totalBodyWaterPct: Double?; let visceralFatIndex: Double?; let metabolicAge: Double?
}
struct PFBodyPoint: Decodable, Identifiable {
    let date: String; let weightKg: Double; let bodyFatPct: Double?
    var id: String { date }
}
struct PFBodyGoal: Decodable, Identifiable {
    let label: String; let unit: String; let start: Double; let target: Double
    let current: Double; let remaining: Double; let progress: Double; let dp: Int; let direction: String
    var id: String { label }
}
