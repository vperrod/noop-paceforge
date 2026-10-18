import Foundation

/// The JSON documents one PaceForge refresh fetches. Only `state` and `fitness` are required;
/// every other document just fills in its own section when it is present.
struct PFRawBundle {
    var state = PFJ(nil)
    var fitness = PFJ(nil)
    var projection = PFJ(nil)
    var body = PFJ(nil)
    var hyrox = PFJ(nil)
    var activities = PFJ(nil)
    var analysesIndex = PFJ(nil)
    var bodyProgress = PFJ(nil)
    var alerts = PFJ(nil)
    var readiness = PFJ(nil)
    var feelSummary = PFJ(nil)
    var whatChanged = PFJ(nil)
    var explainers = PFJ(nil)
    var behaviour = PFJ(nil)
    var raceWeek = PFJ(nil)
    var hyroxSims = PFJ(nil)
    var hyroxSimAnalysis = PFJ(nil)
    var easyMode = PFJ(nil)
    var muscle = PFJ(nil)
    var tape = PFJ(nil)
    var standing = PFJ(nil)
    var insightsV2 = PFJ(nil)
    var dailyIntel = PFJ(nil)
    var healthspan = PFJ(nil)
    var journalImpact = PFJ(nil)
    var highlights = PFJ(nil)
    var monthlyReport = PFJ(nil)
    var myPlan = PFJ(nil)
    var rideMetrics = PFJ(nil)
    var dismissed = PFJ(nil)
    var todayLayout = PFJ(nil)
}

/// Derives the screens' view models from the server's JSON, the way the PaceForge web app derives
/// its own Today / Body / Calendar views.
enum PFBuilder {
    static func snapshot(from raw: PFRawBundle, today: String) -> PFSnapshot? {
        guard raw.state.exists, raw.fitness.exists else { return nil }
        let state = raw.state
        let strength = state["strength_sessions"]
        let allWorkouts = collectWorkouts(state: state, strength: strength, today: today)

        let weeks = buildWeeks(state: state, workouts: allWorkouts, today: today)

        var todayBlock = PFToday()
        let daily = raw.fitness["daily"]
        if let score = daily["recovery"]["score"].double {
            todayBlock.recovery = PFRecovery(score: score, band: daily["recovery"]["band"].string,
                                             confidence: daily["recovery"]["confidence"]["tier"].string,
                                             trust: PFWave2Parse.trust(daily["recovery"]["trust"]))
        }
        if let value = daily["strain"]["value"].double {
            todayBlock.strain = PFStrain(value: value, targetLow: daily["strain"]["target_low"].double,
                                         targetHigh: daily["strain"]["target_high"].double,
                                         band: daily["strain"]["band"].string)
        }
        if let score = daily["sleep"]["score"].double {
            todayBlock.sleep = PFSleep(score: score, hoursText: daily["sleep"]["hours_text"].string,
                                       needText: daily["sleep"]["need_text"].string,
                                       sufficiencyPct: daily["sleep"]["sufficiency_pct"].double,
                                       debtHours: daily["sleep"]["debt_hours"].double)
        }
        todayBlock.hrv = raw.fitness["load"]["hrv"]["last_night_ms"].double
        todayBlock.hrvBaselineMs = raw.fitness["load"]["hrv"]["baseline7_ms"].double
        todayBlock.hrvLowMs = raw.fitness["load"]["hrv"]["normal_range_ms"][0].double
        todayBlock.hrvHighMs = raw.fitness["load"]["hrv"]["normal_range_ms"][1].double
        todayBlock.restingHr = raw.fitness["load"]["resting_hr_trend"]["latest"].double
        todayBlock.acwr = raw.fitness["load"]["acwr"]["acwr"].double
        todayBlock.brief = dailyBrief(state["daily_brief"])
        todayBlock.nextRace = nextRace(events: state["events"], today: today)
        todayBlock.sessions = allWorkouts
            .filter { $0.date == today && $0.status != "optional" }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }

        let insightsV2 = PFInsightsV2Parse.document(raw.insightsV2)
        var snapshot = PFSnapshot(
            generatedAt: state["generated_at"].string,
            todayISO: today,
            today: todayBlock,
            coach: coach(state: state, fitness: raw.fitness),
            weeks: weeks.list,
            currentWeekIndex: weeks.currentIndex,
            insights: insights(fitness: raw.fitness, projection: raw.projection, hyrox: raw.hyrox,
                               raceFinish: insightsV2?.item(PFInsightID.raceCountdown)?.race?.finish,
                               today: today)
        )
        snapshot.body = body(raw.body)
        snapshot.bodyProgress = bodyProgress(raw.bodyProgress)
        snapshot.alerts = alerts(raw.alerts)
        snapshot.readiness = readiness(raw.readiness)
        snapshot.feel = PFWave2Parse.feelSummary(raw.feelSummary)
        snapshot.whatChanged = PFWave2Parse.whatChanged(raw.whatChanged)
        snapshot.behaviour = PFWave2Parse.behaviourImpact(raw.behaviour)
        snapshot.explainers = PFWave2Parse.explainers(raw.explainers)
        snapshot.raceWeek = PFWave3Parse.raceWeek(raw.raceWeek, brief: state["daily_brief"])
        snapshot.simulations = PFWave3Parse.hyroxSims(analysis: raw.hyroxSimAnalysis, sims: raw.hyroxSims)
        // A mode with level 0 or no level is "off"; it must not shadow the brief's mode.
        let activeMode: PFJ = [state["mode"], state["daily_brief"]["mode"]].first { ($0["level"].int ?? 0) > 0 } ?? PFJ(nil)
        snapshot.easyMode = PFWave3Parse.easyMode(raw.easyMode, stateMode: activeMode)
        snapshot.muscle = PFWave3Parse.muscleCheck(raw.muscle)
        snapshot.tape = PFWave3Parse.tape(raw.tape)
        snapshot.standing = PFStandingParse.standing(raw.standing)
        snapshot.insightsV2 = insightsV2
        snapshot.dailyIntel = PFDailyIntelParse.document(raw.dailyIntel)
        snapshot.intelDocs = PFIntelDocsParse.docs(healthspan: raw.healthspan, journalImpact: raw.journalImpact,
                                                   highlights: raw.highlights, monthlyReport: raw.monthlyReport, myPlan: raw.myPlan)
        snapshot.rides = PFRideParse.metrics(raw.rideMetrics)
        snapshot.dismissed = PFDismissStorage.parseServer(raw.dismissed)
        snapshot.todayLayout = PFTodayOrder.parseServer(raw.todayLayout)
        snapshot.serverHidesBody = PFWave3Parse.hidesBodyOnLockScreen(state)
        snapshot.sleepNights = raw.fitness["load"]["sleep"]["stages_14d"].array.compactMap { night in
            guard let date = night["date"].string else { return nil }
            let deep = night["deep_min"].double ?? 0
            let rem = night["rem_min"].double ?? 0
            let light = night["light_min"].double ?? 0
            let minutes = deep + rem + light
            return minutes > 0 ? PFSleepNight(date: date, minutes: minutes) : nil
        }
        for item in raw.activities.array {
            if let activity = activity(item) { snapshot.activities[activity.id] = activity }
        }
        for row in raw.analysesIndex.array {
            if let parsed = analysisRow(row) { snapshot.analyses[parsed.id] = parsed }
        }
        for row in raw.fitness["load"]["daily_load"]["per_activity"].array {
            if let id = row["activity_id"].idString, let trimp = row["trimp"].double { snapshot.trimp[id] = trimp }
        }
        for entry in state["rpe"]["entries"].array {
            if let id = entry["activity_id"].idString, let rpe = entry["rpe"].double { snapshot.rpe[id] = rpe }
        }
        return snapshot
    }

    // MARK: Workouts

    private static func collectWorkouts(state: PFJ, strength: PFJ, today: String) -> [PFWorkout] {
        var byId: [String: PFJ] = [:]
        var order: [String] = []
        func add(_ w: PFJ) {
            guard let id = w["session_id"].string, w["workout_type"].string != "rest" else { return }
            if byId[id] == nil { order.append(id) }
            byId[id] = w
        }
        for week in state["plan"]["weeks"].array {
            for w in week["workouts"].array { add(w) }
        }
        for w in state["calendar"].array { add(w) }
        return order.compactMap { id in byId[id].map { workout($0, strength: strength, today: today) } }
    }

    static func workout(_ w: PFJ, strength: PFJ, today: String) -> PFWorkout {
        let cm = w["completion_metrics"]
        let id = w["session_id"].string ?? ""
        let date = w["scheduled_date"].string ?? ""

        let status: String
        if w["completed"].bool == true {
            status = w["status"].string == "partial" ? "partial" : "done"
        } else if w["state"].string == "optional" {
            status = "optional"
        } else if cm["status"].string == "red" || date < today {
            status = "missed"
        } else {
            status = "planned"
        }

        let exercises: [PFExercise] = strength[id]["exercises"].array.compactMap { e in
            guard let name = e["name"].string else { return nil }
            let cue = e["cue"].string?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).trimmingCharacters(in: .whitespaces)
            return PFExercise(name: name, sets: e["sets"].double, reps: e["reps"].idString,
                              rpe: e["rpe"].double, cue: (cue?.isEmpty ?? true) ? nil : cue)
        }

        var out = PFWorkout(id: id, date: date, status: status)
        out.name = w["name"].string
        out.kind = w["workout_type"].string
        out.sport = w["sport"].string
        if let secs = w["estimated_duration_seconds"].double, secs > 0 { out.durationMin = (secs / 60).rounded() }
        if let meters = w["estimated_distance_meters"].double, meters > 0 { out.distanceKm = (meters / 100).rounded() / 10 }
        out.targetRpe = w["target_rpe"].double
        out.userRpe = w["user_rpe"].double
        out.cadenceTarget = w["cadence_target"].double
        out.description = exercises.isEmpty ? w["description"].text : nil
        out.briefing = briefing(w["briefing"])
        out.steps = w["steps"].array.map { step($0) }
        out.exercises = exercises
        if cm.exists {
            out.compliance = PFCompliance(status: cm["status"].string, ratio: cm["ratio"].double,
                                          plannedKm: cm["planned_km"].double, actualKm: cm["actual_km"].double,
                                          plannedMin: cm["planned_min"].double, actualMin: cm["actual_min"].double)
        }
        out.completionAnalysis = w["completion_analysis"].text
        out.notes = w["notes"].text
        out.activityId = w["matched_activity_ids"].array.compactMap { $0.idString }.first
            ?? w["manual_activity_ids"].array.compactMap { $0.idString }.first
            ?? cm["activity_id"].idString
        return out
    }

    private static func briefing(_ b: PFJ) -> PFBriefing? {
        guard b.exists else { return nil }
        let out = PFBriefing(purpose: b["purpose"].text, structure: b["structure"].text, feel: b["feel"].text,
                             ifWrong: b["if_wrong"].text, cue: b["cue"].text, venue: b["venue"].text,
                             fuel: b["fuel"].text, warmup: b["warmup"].text)
        let all = [out.purpose, out.structure, out.feel, out.ifWrong, out.cue, out.venue, out.fuel, out.warmup]
        return all.contains { $0 != nil } ? out : nil
    }

    private static func step(_ s: PFJ) -> PFStep {
        var out = PFStep()
        out.type = s["step_type"].string
        out.description = s["description"].string
        out.durationSec = s["duration_seconds"].double
        out.distanceM = s["distance_meters"].double
        let targetType = s["target_type"].string
        out.targetType = targetType == "open" ? nil : targetType
        out.targetLow = s["target_low"].double
        out.targetHigh = s["target_high"].double
        out.repeatCount = s["repeat_count"].int
        out.steps = s["steps"].array.map { step($0) }
        return out
    }

    // MARK: Weeks

    private static func buildWeeks(state: PFJ, workouts: [PFWorkout], today: String) -> (list: [PFWeek], currentIndex: Int) {
        let monday = PFFormat.monday(of: today)
        let starts = [PFFormat.addDays(monday, -7), monday, PFFormat.addDays(monday, 7)]
        let list = starts.map { week(start: $0, state: state, workouts: workouts) }
        return (list, 1)
    }

    private static func week(start: String, state: PFJ, workouts: [PFWorkout]) -> PFWeek {
        let end = PFFormat.addDays(start, 6)
        let key = PFFormat.isoWeekKey(start)
        let dows = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let days: [PFDay] = (0..<7).map { i in
            let date = PFFormat.addDays(start, i)
            let ws = workouts.filter { $0.date == date }.sorted { a, b in
                let ao = a.status == "optional", bo = b.status == "optional"
                if ao != bo { return !ao }
                let ad = a.status == "done" || a.status == "partial"
                let bd = b.status == "done" || b.status == "partial"
                if ad != bd { return ad }
                return (a.name ?? "") < (b.name ?? "")
            }
            return PFDay(date: date, dow: dows[i], workouts: ws)
        }
        var out = PFWeek(key: key, start: start, end: end, days: days)

        let planWeek = state["plan"]["weeks"].array.first { pw in
            pw["workouts"].array.contains { w in
                guard let d = w["scheduled_date"].string else { return false }
                return d >= start && d <= end
            }
        }
        out.phase = planWeek?["phase"].string
        out.focus = planWeek?["focus"].text
        let plan = state["week_plans"][key]
        out.intro = plan["line"].text
        out.targetHours = plan["target"].double
        let tally = state["week_tally"]
        if tally["week_start"].string == start { out.tally = tally["label"].text }
        let review = state["weekly_review"]
        if review["week"].string == key { out.headline = review["headline"].text }
        let doc = state["week_plan_doc"]
        if doc["week"].string == key { out.plannedHours = doc["planned"].double }
        return out
    }

    // MARK: Today

    private static func dailyBrief(_ b: PFJ) -> PFDailyBrief? {
        guard let headline = b["headline"].text else { return nil }
        var out = PFDailyBrief(headline: headline)
        out.date = b["date"].string
        out.notes = b["notes"].array.compactMap { $0.text }
        out.outlook = b["outlook"].array.compactMap { $0.text }
        out.bodyState = b["body_state"].text
        out.training = b["training"].text ?? b["session"].text
        out.recent = b["recent"].text
        out.focus = b["focus"].array.compactMap { $0.text }
        out.pulses = b["pulses"].array.compactMap { p in
            guard let text = p["text"].text else { return nil }
            return PFPulse(at: p["at"].string, text: text)
        }
        out.partial = b["partial"].bool ?? false
        out.missing = b["missing"].array.compactMap { $0.text }
        if out.partial && out.missing.isEmpty {
            // An older shape: only the per-input flags say what is missing. A null scale means it is not expected.
            if b["inputs"]["sleep"].bool == false { out.missing.append("sleep") }
            if b["inputs"]["hrv"].bool == false { out.missing.append("HRV") }
            if b["inputs"]["scale"].bool == false { out.missing.append("scale") }
        }
        out.updatedAt = b["updated_at"].text
        out.updateCount = b["update_count"].int ?? 0
        out.changes = b["changes"].text
        return out
    }

    // MARK: Newer files (every field optional)

    /// The text of a JSON scalar or a short list of numbers, e.g. "10-13" for [10, 13].
    private static func scalarText(_ j: PFJ) -> String? {
        if let text = j.text { return text }
        if let number = j.double { return PFFormat.trimmed(number) }
        let numbers = j.array.compactMap { $0.double }
        if numbers.count >= 2 { return numbers.map(PFFormat.trimmed).joined(separator: "\u{2013}") }
        return nil
    }

    /// Your own usual hydration: `{total_body_water_pct, ecw_icw_ratio}`, either of them possibly null.
    private static func ownNormal(_ j: PFJ) -> String? {
        var parts: [String] = []
        if let pct = j["total_body_water_pct"].double { parts.append(PFFormat.oneDecimal(pct) + "%") }
        if let ratio = j["ecw_icw_ratio"].double { parts.append("ECW/ICW " + String(format: "%.2f", ratio)) }
        if !parts.isEmpty { return "your normal " + parts.joined(separator: ", ") }
        return scalarText(j)
    }

    /// Decodes the new `hrr1` object and the older `{bpm, kind: post|mid, …}` one. An older `mid` is an
    /// estimated interval rebound. A figure that is missing its `bpm` is only kept when the server says
    /// why (`not_measurable`, `walking`, `no_post_stop_data`, `garmin_2min`).
    static func hrr1(_ j: PFJ) -> PFHRR1? {
        let bpm = j["bpm"].int
        var kind = j["kind"].text ?? PFHRR1.post
        var isEstimated = false
        if kind == "mid" { kind = PFHRR1.interval; isEstimated = true }
        if bpm == nil {
            guard j.exists, j["kind"].text != nil else { return nil }
            if ![PFHRR1.walking, PFHRR1.noPostStopData, PFHRR1.garmin2min].contains(kind) { kind = PFHRR1.notMeasurable }
        }
        return PFHRR1(bpm: bpm, kind: kind, bpm120: j["bpm120"].int, stopBpm: j["stop_bpm"].int,
                      peakBpm: j["peak_bpm"].int, risingAfterStop: j["rising_after_stop"].bool ?? false,
                      contextBand: j["context_band"].text, baselineBpm: j["baseline_bpm"].double,
                      delta: j["delta"].double, band: j["band"].text, isEstimated: isEstimated,
                      reason: j["reason"].text,
                      readings: j["readings"].array.compactMap { r in
                          guard let offset = r["offset_s_from_stop"].int, let value = r["bpm"].int else { return nil }
                          return PFHRR1.Reading(offsetSeconds: offset, bpm: value, drop: r["drop_bpm"].int)
                      },
                      label: j["label"].text)
    }

    static func bodyProgress(_ b: PFJ) -> PFBodyProgress? {
        guard b.exists, b["has_data"].bool != false else { return nil }
        var out = PFBodyProgress()
        out.date = b["date"].string
        out.latestReadingDate = b["latest_reading_date"].string
        out.digest = b["digest"].text
        out.goals = b["goals"].array.compactMap { g in
            guard let metric = g["metric"].string else { return nil }
            return PFProgressGoal(
                metric: metric, label: g["label"].string ?? metric, unit: g["unit"].string ?? "",
                target: g["target"].double, targetDate: g["target_date"].string,
                startValue: g["start_value"].double, startDate: g["start_date"].string,
                current7d: g["current_7d"].double, lastReading: g["last_reading"].double,
                neededPerWeek: g["needed_per_week"].double, actualPerWeek: g["actual_per_week"].double,
                eta: g["eta"].text, status: g["status"].string ?? "insufficient_data",
                aggressive: g["aggressive"].bool ?? false)
        }
        out.noiseWeightKg = b["noise_band"]["weight_kg"].double
        out.noiseBodyFatPct = b["noise_band"]["body_fat_pct"].double
        out.noiseBasis = b["noise_basis"].text
        out.dailyLine = b["daily_line"].text
        let fuel = b["fuel"]
        if fuel.exists {
            out.fuel = PFFuel(bmrKcal: fuel["bmr_kcal"].double, trainingDayKcal: fuel["training_day_kcal_estimate"].double,
                              trainingDayBasis: fuel["training_day_basis"].text,
                              proteinLow: fuel["protein_g"]["low"].double, proteinHigh: fuel["protein_g"]["high"].double,
                              proteinBasis: fuel["protein_g"]["basis"].text)
        }
        let water = b["hydration"]
        if water.exists {
            out.hydration = PFHydration(waterPct: water["water_pct"].double, ecwIcwRatio: water["ecw_icw_ratio"].double,
                                        flag: water["flag"].text, reason: water["reason"].text,
                                        ownNormal: ownNormal(water["own_normal"]))
        }
        let balance = b["balance"]
        if balance.exists {
            out.balance = PFBalance(armsPct: balance["arms_pct"].double, legsPct: balance["legs_pct"].double,
                                    maxPct: balance["max_pct"].double, flag: balance["flag"].text,
                                    note: balance["note"].text, estimate: balance["estimate"].bool,
                                    method: balance["method"].text)
        }
        let visceral = b["visceral"]
        if visceral.exists {
            out.visceral = PFVisceral(value: visceral["value"].double, band: visceral["band"].text,
                                      standardRange: scalarText(visceral["standard_range"]))
        }
        if let text = b["analysis"]["text"].text {
            out.analysis = PFProgressAnalysis(text: text, generatedAt: b["analysis"]["generated_at"].string)
        }
        let hasContent = !out.goals.isEmpty || out.digest != nil || out.dailyLine != nil || out.fuel != nil
            || out.hydration != nil || out.balance != nil || out.visceral != nil || out.analysis != nil
        return hasContent ? out : nil
    }

    /// Open alerts, most urgent first, then newest first.
    static func alerts(_ j: PFJ) -> [PFAlert] {
        let open: [PFAlert] = j["alerts"].array.compactMap { a in
            guard let id = a["id"].idString, let title = a["title"].text,
                  (a["status"].string ?? "open") == "open" else { return nil }
            let actions: [PFAlertAction] = a["actions"].array.compactMap { action in
                guard let label = action["label"].text else { return nil }
                return PFAlertAction(id: action["id"].string ?? label, label: label)
            }
            return PFAlert(id: id, kind: a["kind"].string, severity: a["severity"].string ?? "info",
                           createdAt: a["created_at"].string, title: title, body: a["body"].text, actions: actions)
        }
        return open.sorted { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : (lhs.createdAt ?? "") > (rhs.createdAt ?? "")
        }
    }

    static func readiness(_ j: PFJ) -> PFReadiness? {
        guard j.exists else { return nil }
        let sources: [PFReadinessSource] = j["sources"].array.compactMap { s in
            guard let name = s["source"].string else { return nil }
            let factors: [PFReadinessFactor] = s["factors"].array.compactMap { f in
                guard let factor = f["name"].text else { return nil }
                return PFReadinessFactor(name: factor, value: scalarText(f["value"]), status: f["status"].text)
            }
            let drivers: [String] = s["drivers"].array.compactMap { d in
                d.text ?? d["name"].text ?? d["label"].text
            }
            return PFReadinessSource(source: name, score: s["score"].double, band: s["band"].text ?? s["level"].text,
                                     drivers: drivers, factors: factors, recoveryTimeH: s["recovery_time_h"].double,
                                     hrv: s["hrv"].double, rhr: s["rhr"].double,
                                     sleepPerformance: s["sleep_performance"].double,
                                     trust: PFWave2Parse.trust(s["trust"]))
        }
        guard !sources.isEmpty else { return nil }
        return PFReadiness(date: j["date"].string, sources: sources, agreement: j["agreement"].text,
                           coachNote: j["coach_note"].text, answers: PFWave2Parse.answers(j["answers"]))
    }

    private static func nextRace(events: PFJ, today: String) -> PFNextRace? {
        let upcoming = events.array
            .filter { ($0["date"].string ?? "") >= today && $0["name"].string != nil }
            .sorted { ($0["date"].string ?? "") < ($1["date"].string ?? "") }
        guard let first = upcoming.first, let name = first["name"].string, let date = first["date"].string else { return nil }
        return PFNextRace(name: name, date: date, daysOut: PFFormat.daysBetween(today, date), goalTime: first["goal_time"].text)
    }

    // MARK: Coach

    private static func coach(state: PFJ, fitness: PFJ) -> PFCoach {
        var out = PFCoach()
        let daily = state["daily_brief"]
        if let headline = daily["headline"].text {
            out.brief = PFBrief(date: daily["date"].string, headline: headline, outlook: daily["outlook"].strings)
        }
        if let headline = fitness["headline"].text {
            let readiness = fitness["coach_input"]["readiness"]
            out.take = PFTake(
                headline: headline,
                readinessScore: readiness["score"].double,
                readinessBand: readiness["band"].string,
                limiters: fitness["limiters"].array.compactMap { l in
                    guard let name = l["name"].string else { return nil }
                    return PFLimiter(name: name, area: l["area"].string ?? "", evidence: l["evidence"].string ?? "",
                                     recommendation: l["recommendation"].string ?? "")
                },
                weekActions: fitness["this_week"].array.compactMap { a in
                    guard let action = a["action"].string else { return nil }
                    return PFWeekAction(area: a["area"].string ?? "", action: action)
                })
        }
        let review = state["weekly_review"]
        if let headline = review["headline"].text, let start = review["period"]["start"].string,
           let end = review["period"]["end"].string {
            let weekly = state["weekly"]
            out.weeklyReview = PFWeeklyReview(
                week: review["week"].string ?? "",
                period: PFPeriod(start: start, end: end),
                headline: headline,
                limiters: weekly["limiters"].strings,
                plannedRuns: review["done"]["planned_runs"].int,
                completedRuns: review["done"]["completed_runs"].int,
                qualityDone: review["done"]["quality_done"].int,
                sessions: review["sessions"].array.compactMap { s in
                    guard let date = s["date"].string, let name = s["name"].string else { return nil }
                    return PFReviewSession(date: date, name: name, completed: s["completed"].bool ?? false,
                                           quality: s["quality"].bool ?? false, status: s["status"].string)
                },
                fatigue: review["fatigue"]["signals"].array.compactMap { f in
                    guard let text = f["text"].text else { return nil }
                    return PFFatigue(kind: f["kind"].string, text: text)
                },
                strengthSaid: review["strength"]["said"].text,
                thisWeek: weekly["this_week"].strings)
        }
        out.chat = state["chat"]["turns"].array.suffix(6).compactMap { t in
            guard let role = t["role"].string, let text = t["text"].text, let ts = t["ts"].string else { return nil }
            return PFChatTurn(role: role, text: text, ts: ts)
        }
        return out
    }

    // MARK: Insights

    private static func insights(fitness: PFJ, projection: PFJ, hyrox: PFJ, raceFinish: PFFinishRange?,
                                 today: String) -> PFInsights {
        let pmc = fitness["load"]["ctl_atl_tsb"]
        var out = PFInsights(ctl: pmc["ctl"].double ?? 0, atl: pmc["atl"].double ?? 0, tsb: pmc["tsb"].double ?? 0)
        out.formBand = pmc["friel_band"].string
        out.history = pmc["series"].array.suffix(90).compactMap(loadPoint)

        let horizon = PFFormat.addDays(today, 35)
        out.projection = projection["series"].array
            .filter { ($0["date"].string ?? "") > today && ($0["date"].string ?? "") <= horizon }
            .compactMap(loadPoint)
        out.markers = projection["events"].array
            .filter { ($0["date"].string ?? "") <= horizon }
            .compactMap { e in
                guard let date = e["date"].string, let name = e["name"].string else { return nil }
                return PFMarker(date: date, name: name)
            }
        out.warnings = projection["warnings"].array.prefix(5).compactMap { w in
            guard let date = w["date"].string, let text = w["text"].text else { return nil }
            return PFWarning(date: date, text: text)
        }
        out.loadSentence = projection["sentences"]["load"].text
        out.races = projection["event_cards"].array.compactMap { c in
            guard let name = c["name"].string, let date = c["date"].string, let days = c["days_out"].int else { return nil }
            return PFRace(name: name, date: date, daysOut: days, headline: c["headline"].string ?? "",
                          readiness: c["readiness"].string ?? "", taperOk: c["taper_ok"].bool)
        }
        // Only a road-race goal has a running prognosis; a HYROX goal's server prognosis is `available: false`.
        if let running = PFHyroxPrognosisParse.runningAgainstGoal(fitness["prognosis"]) {
            out.goalPrognosis = PFGoalPrognosis(prognosisSec: running.prognosisSec, goalSec: running.goalSec,
                                                verdict: running.verdict,
                                                sentence: projection["sentences"]["running"].text)
        }
        out.hyroxFinish = PFHyroxPrognosisParse.card(finish: raceFinish, hyrox: hyrox)
        let prediction = hyrox["prediction"]
        if let predicted = prediction["predicted_display"].string {
            let stations: [PFStation] = hyrox["priorities"].array
                .filter { $0["train_priority"].bool == true }
                .prefix(4)
                .compactMap { s in
                    guard let name = s["display"].string else { return nil }
                    return PFStation(name: name, athlete: s["athlete_display"].string ?? "",
                                     top3: s["top3_avg_display"].string ?? "", gapSec: s["gap_seconds"].double ?? 0)
                }
            out.hyrox = PFHyrox(predicted: predicted, basis: prediction["basis"].text, trend: prediction["trend"].string,
                                sentence: projection["sentences"]["hyrox"].text, stations: stations)
        }
        return out
    }

    private static func loadPoint(_ p: PFJ) -> PFLoadPoint? {
        guard let date = p["date"].string, let ctl = p["ctl"].double, let atl = p["atl"].double,
              let tsb = p["tsb"].double else { return nil }
        return PFLoadPoint(date: date, ctl: ctl, atl: atl, tsb: tsb)
    }

    // MARK: Body

    private static let bodyNames: [(String, String)] = [
        ("right_arm", "Right arm"), ("left_arm", "Left arm"), ("trunk", "Trunk"),
        ("right_leg", "Right leg"), ("left_leg", "Left leg"),
    ]

    static func body(_ b: PFJ) -> PFBodyDoc? {
        guard b["has_data"].bool != false, let date = b["latest"]["date"].string else { return nil }
        var out = PFBodyDoc(date: date)
        out.score = b["score"].double
        out.band = b["band"].text
        out.age = b["profile"]["age"].int
        out.heightCm = b["profile"]["height_cm"].double

        out.assessment = b["assessment"].array.compactMap { r in
            guard let key = r["key"].string, let value = r["value"].double, let low = r["low"].double,
                  let high = r["high"].double, let lo = r["scale_lo"].double, let hi = r["scale_hi"].double else { return nil }
            return PFBodyRange(key: key, label: r["label"].string ?? key, unit: r["unit"].string ?? "", value: value,
                               dp: r["dp"].int ?? 1, low: low, high: high, scaleLo: lo, scaleHi: hi,
                               pos: r["pos"].double ?? 0, status: r["status"].string ?? "standard")
        }
        for (key, value) in b["latest"].dict {
            if let number = value.double { out.latest[key] = number }
        }
        out.segments = bodyNames.compactMap { key, name in
            let s = b["latest"]["segmental"][key]
            guard s.exists else { return nil }
            return PFBodySegment(key: key, name: name, weightKg: s["weight_kg"].double, fatKg: s["fat_kg"].double,
                                 ffmKg: s["ffm_kg"].double, muscleKg: s["muscle_kg"].double)
        }
        out.series = b["series"].array.compactMap { r in
            guard let date = r["date"].string else { return nil }
            var values: [String: Double] = [:]
            for (key, value) in r.dict {
                if let number = value.double { values[key] = number }
            }
            return PFBodyReading(date: date, values: values)
        }
        out.goals = b["goals"].array.compactMap { g in
            guard let metric = g["metric"].string, let target = g["target"].double, let current = g["current"].double else { return nil }
            return PFBodyGoal(metric: metric, label: g["label"].string ?? metric, unit: g["unit"].string ?? "",
                              target: target, current: current, remaining: g["remaining"].double,
                              progress: g["progress"].double, dp: g["dp"].int ?? 1,
                              reached: g["reached"].bool ?? false, targetDate: g["target_date"].string)
        }
        for (key, value) in b["deltas"].dict {
            out.deltas[key] = PFBodyDelta(d7: value["d7"].double, d30: value["d30"].double, d90: value["d90"].double)
        }
        for (key, value) in b["metrics"].dict {
            out.metrics[key] = PFBodyMetric(label: value["label"].string ?? key, unit: value["unit"].string ?? "",
                                            dp: value["dp"].int ?? 1, good: value["good"].string ?? "flat")
        }
        out.segmentalMeta = PFWave3Parse.segmentalMeta(b["latest"]["segmental_meta"])
        return out
    }

    // MARK: Activities

    static func activity(_ a: PFJ) -> PFActivity? {
        guard let id = a["activity_id"].idString else { return nil }
        var out = PFActivity(id: id)
        out.name = a["name"].string
        out.type = a["activity_type"].string
        out.startTime = a["start_time"].string
        out.distanceM = a["distance_meters"].double
        out.durationS = a["duration_seconds"].double
        out.avgHr = a["avg_hr"].double
        out.maxHr = a["max_hr"].double
        out.avgPaceSecPerKm = a["avg_pace_sec_per_km"].double
        out.calories = a["calories"].double
        out.teAerobic = a["training_effect_aerobic"].double
        out.teAnaerobic = a["training_effect_anaerobic"].double
        out.cadence = a["avg_running_cadence"].double
        out.strideCm = a["avg_stride_length"].double
        out.groundContactMs = a["avg_ground_contact_time"].double
        out.avgPower = a["avg_power"].double
        out.elevationM = a["elevation_gain"].double
        out.hrr1 = hrr1(a["hrr1"])
        out.hrrGarmin = PFHRRGarmin.parse(a["hrr_garmin"])
        out.heat = PFWave3Parse.heat(a["heat"])
        return out
    }

    static func detail(_ d: PFJ) -> PFDetail {
        var out = PFDetail()
        out.hrr1 = hrr1(d["hrr1"])
        out.hrrGarmin = PFHRRGarmin.parse(d["hrr_garmin"])
        out.samples = d["series"].array.compactMap { s in
            guard let t = s["t"].double else { return nil }
            return PFSample(t: t, hr: s["hr"].double, pace: s["pace"].double, cad: s["cad"].double)
        }
        out.splits = d["splits"].array.enumerated().map { index, s in
            PFSplit(n: s["n"].int ?? index + 1, distanceM: s["distance_m"].double, paceSec: s["pace_sec"].double,
                    avgHr: s["avg_hr"].double, elevGain: s["elev_gain"].double)
        }
        out.zones = d["hr_zones"].array.compactMap { z in
            guard let zone = z["zone"].int, (1...5).contains(zone) else { return nil }
            return PFZone(zone: zone, secs: z["secs"].double ?? 0, low: z["low"].double)
        }
        let w = d["weather"]
        if w["temp_c"].double != nil || w["desc"].text != nil {
            out.weather = PFWeather(tempC: w["temp_c"].double, desc: w["desc"].text)
        }
        return out
    }

    static func analysisRow(_ r: PFJ) -> PFAnalysisRow? {
        guard let id = r["id"].idString else { return nil }
        var out = PFAnalysisRow(id: id)
        out.headline = r["headline"].text
        let insights = r["insights"]
        let strain = insights["strain"]
        if strain["available"].bool == true { out.strain = strain["value"].double }
        out.strainBand = strain["band"].text
        let impact = insights["recovery_impact"]
        if impact["available"].bool == true { out.recoveryReason = impact["reason"].text }
        let typical = insights["vs_typical"]
        if typical["available"].bool == true {
            let samples = typical["samples"].int ?? 0
            let type = (typical["type"].string ?? "").replacingOccurrences(of: "_", with: " ")
            if let p = typical["metrics"]["strain"]["percentile"].double {
                out.vsTypicalPercentile = p
                out.vsTypicalLabel = "of your \(samples) \(type) sessions"
            } else if let p = typical["metrics"]["duration_min"]["percentile"].double {
                out.vsTypicalPercentile = p
                out.vsTypicalLabel = "by duration, \(samples) sessions"
            }
            out.vsTypicalReason = typical["reason"].text
        }
        let plan = insights["planned_vs_actual"]
        out.plannedKm = plan["planned_km"].double
        out.plannedMin = plan["planned_minutes"].double
        out.actualKm = plan["actual_km"].double
        out.actualMin = plan["actual_minutes"].double
        return out
    }
}
