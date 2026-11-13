import Foundation

// `data/today-call.json`: the one document the unified Today reads for its first cards (the call, today / next race, how you are, this
// week). Foundation only, so it is compiled into the macOS unit-test bundle with the builder. Every field may be missing: an older
// server serves no such file, and the Today cards then fall back to the snapshot's own data (`PFTodayCall.fallback`).

struct PFTodayCall: Equatable {
    struct Call: Equatable {
        var verdict: String
        var reason: String
        var source: String?
    }

    struct TodayBlock: Equatable {
        /// "race", "session", "rest" or "none".
        var kind: String
        var title: String?
        var detail: String?
        var sessionID: String?
        var raceDate: String?
    }

    struct Race: Equatable {
        var name: String
        var date: String
        var daysOut: Int
        var goalTime: String?
    }

    struct Device: Equatable {
        var score: Double?
        var band: String?
        var label: String?
    }

    struct HRVRange: Equatable {
        var low: Double
        var high: Double
        var lastNight: Double?
    }

    struct Readiness: Equatable {
        var garmin = Device()
        var strap = Device()
        var own = Device()
        /// Whether the card may show PaceForge's own score. The Today card shows Garmin and WHOOP only, so the server sends false.
        var ownShow = false
        /// Garmin's readiness factors, recovery time (hours) and HRV normal range; each is absent when the server omits it.
        var garminFactors: [String] = []
        var garminRecoveryHours: Double?
        var garminHRV: HRVRange?
        /// "agree", "differ" or "unknown".
        var agreement = "unknown"
        var sleepMinutes: Int?
        var sleepNeedMinutes: Int?

        /// The factors line: at most three, joined with a middle dot.
        var factorsLine: String? {
            garminFactors.isEmpty ? nil : garminFactors.prefix(3).joined(separator: " \u{00B7} ")
        }

        var recoveryLine: String? {
            garminRecoveryHours.map { "Recovery time \(Int($0.rounded())) h" }
        }

        var hrvLine: String? {
            guard let hrv = garminHRV else { return nil }
            var out = "HRV normal \(Int(hrv.low.rounded()))\u{2013}\(Int(hrv.high.rounded())) ms"
            if let last = hrv.lastNight { out += ", last night \(Int(last.rounded()))" }
            return out
        }

        /// The Garmin column's lines, in order, only those the server sent.
        var garminLines: [String] { [factorsLine, recoveryLine, hrvLine].compactMap { $0 } }
    }

    struct WeekItem: Equatable {
        /// "session", "race", "ride", "dayoff" or "test".
        var kind: String
        var title: String
        /// "done", "planned", "missed", "partial" or "optional".
        var status: String
        var sessionID: String?
        /// A race that was run: the finish ("1:08:13"), its source ("official" or "garmin"), the gap to the goal in seconds
        /// (positive = slower) and the recording's activity id.
        var result: String? = nil
        var resultSource: String? = nil
        var goalDeltaSeconds: Int? = nil
        var activityID: String? = nil
    }

    struct WeekDay: Equatable {
        var date: String
        var dow: String
        var items: [WeekItem]
    }

    var date: String?
    var generatedAt: String?
    var call: Call?
    var today = TodayBlock(kind: "none")
    var nextRace: Race?
    var readiness = Readiness()
    var needsYou = 0
    var week: [WeekDay] = []

    var hasReadiness: Bool {
        readiness.garmin.score != nil || readiness.strap.score != nil || readiness.own.score != nil
    }
}

enum PFTodayCallParse {
    /// The document, or nil when it is missing or has none of the parts the cards draw.
    static func document(_ j: PFJ) -> PFTodayCall? {
        guard j.exists, j.raw is [String: Any] else { return nil }
        var out = PFTodayCall()
        out.date = j["date"].text
        out.generatedAt = j["generated_at"].text
        if let verdict = j["call"]["verdict"].text {
            out.call = PFTodayCall.Call(verdict: verdict, reason: j["call"]["reason"].text ?? "", source: j["call"]["source"].text)
        }
        let today = j["today"]
        out.today = PFTodayCall.TodayBlock(kind: today["kind"].text ?? "none", title: today["title"].text, detail: today["detail"].text,
                                           sessionID: today["session_id"].idString, raceDate: today["race_date"].text)
        let race = j["next_race"]
        if let name = race["name"].text, let date = race["date"].text {
            out.nextRace = PFTodayCall.Race(name: name, date: date, daysOut: race["days_out"].int ?? 0, goalTime: race["goal_time"].text)
        }
        out.readiness = readiness(j["readiness"])
        out.needsYou = max(0, j["needs_you"].int ?? 0)
        out.week = j["week"].array.compactMap { day in
            guard let date = day["date"].text else { return nil }
            let items: [PFTodayCall.WeekItem] = day["items"].array.compactMap { item in
                guard let title = item["title"].text else { return nil }
                return PFTodayCall.WeekItem(kind: item["kind"].text ?? "session", title: title, status: item["status"].text ?? "planned",
                                            sessionID: item["session_id"].idString, result: item["result"]["display"].text,
                                            resultSource: item["result"]["source"].text, goalDeltaSeconds: item["result"]["goal_delta_s"].int,
                                            activityID: item["activity_id"].idString)
            }
            return PFTodayCall.WeekDay(date: date, dow: day["dow"].text ?? "", items: items)
        }
        let hasContent = out.call != nil || out.nextRace != nil || out.hasReadiness || !out.week.isEmpty || out.today.kind != "none"
        return hasContent ? out : nil
    }

    private static func device(_ j: PFJ) -> PFTodayCall.Device {
        PFTodayCall.Device(score: j["score"].double, band: j["band"].text, label: j["label"].text)
    }

    private static func readiness(_ j: PFJ) -> PFTodayCall.Readiness {
        var out = PFTodayCall.Readiness()
        out.garmin = device(j["garmin"])
        out.strap = device(j["strap"])
        out.own = device(j["own"])
        out.ownShow = j["own"]["show"].bool ?? false
        let garmin = j["garmin"]
        out.garminFactors = garmin["factors"].strings.filter { !$0.isEmpty }
        out.garminRecoveryHours = garmin["recovery_time_h"].double.flatMap { $0 >= 0 ? $0 : nil }
        let hrv = garmin["hrv_range_ms"]
        if let low = hrv["low"].double, let high = hrv["high"].double {
            out.garminHRV = PFTodayCall.HRVRange(low: low, high: high, lastNight: hrv["last_night"].double)
        }
        out.agreement = j["agreement"].text ?? "unknown"
        out.sleepMinutes = j["sleep"]["minutes"].int
        out.sleepNeedMinutes = j["sleep"]["need_minutes"].int
        return out
    }

    /// What the cards show when the server serves no `today-call.json`: the same parts from the snapshot's own data. The week strip
    /// is the current week of the plan; the call is the brief's headline. Nothing is invented: a part the snapshot lacks stays empty.
    static func fallback(from snapshot: PFSnapshot) -> PFTodayCall {
        var out = PFTodayCall()
        out.date = snapshot.todayISO
        if let brief = snapshot.today.brief {
            out.call = PFTodayCall.Call(verdict: brief.headline, reason: brief.notes.first ?? "", source: nil)
        }
        if let race = snapshot.races(on: snapshot.todayISO).first {
            out.today = PFTodayCall.TodayBlock(kind: "race", title: race.name, detail: race.goalTime, sessionID: nil, raceDate: race.date)
        } else if let session = snapshot.today.sessions.first {
            out.today = PFTodayCall.TodayBlock(kind: "session", title: session.name, detail: nil, sessionID: session.coachSessionID ?? session.id, raceDate: nil)
        } else {
            out.today = PFTodayCall.TodayBlock(kind: "rest", title: nil, detail: nil, sessionID: nil, raceDate: nil)
        }
        if let race = snapshot.today.nextRace {
            out.nextRace = PFTodayCall.Race(name: race.name, date: race.date, daysOut: race.daysOut, goalTime: race.goalTime)
        }
        if let recovery = snapshot.today.recovery {
            out.readiness.garmin = PFTodayCall.Device(score: recovery.score, band: recovery.band, label: nil)
        }
        out.needsYou = snapshot.needsYou.count
        if snapshot.weeks.indices.contains(snapshot.currentWeekIndex) {
            out.week = snapshot.weeks[snapshot.currentWeekIndex].days.map { day in
                var items = day.workouts.map {
                    PFTodayCall.WeekItem(kind: "session", title: $0.name ?? "Session", status: $0.status, sessionID: $0.coachSessionID ?? $0.id)
                }
                items += snapshot.races(on: day.date).map { PFTodayCall.WeekItem(kind: "race", title: $0.name, status: "planned", sessionID: nil) }
                return PFTodayCall.WeekDay(date: day.date, dow: String(day.dow.prefix(3)), items: items)
            }
        }
        return out
    }
}

/// The glyph a day of the week strip shows: ● done, ○ planned, 🏁 race, – rest.
enum PFWeekGlyph {
    static func glyph(for day: PFTodayCall.WeekDay) -> String {
        if day.items.contains(where: { $0.kind == "race" }) { return "\u{1F3C1}" }
        let sessions = day.items.filter { $0.kind != "dayoff" }
        if sessions.isEmpty { return "\u{2013}" }
        if sessions.allSatisfy({ $0.status == "done" || $0.status == "partial" }) { return "\u{25CF}" }
        return "\u{25CB}"
    }
}

extension PFTodayCall.WeekItem {
    /// "+8:13 vs goal" / "-0:40 vs goal" for a run race with a goal, else nil.
    var goalGapLine: String? {
        guard let delta = goalDeltaSeconds else { return nil }
        let seconds = abs(delta)
        return "\(delta > 0 ? "+" : "-")\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60) vs goal"
    }
}
