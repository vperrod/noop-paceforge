import Foundation

// Three things the athlete can do from the iPhone that used to be web-only: change the details of a planned session, add a planned session,
// and log a workout he did himself so the coach can read it. Foundation only, so it is compiled into the macOS unit-test bundle.
// Jobs: `calendar-edit` (action `edit`), `add-session`, `manual-workout`, `manual-workout-edit`, `manual-workout-delete`, `manual-workout-comment` (PaceForgeJob.swift);
// the list of logged workouts is `GET manual-workouts`. Every limit below is the server's own, so the app never sends what it would refuse.

enum PFManualPlan {
    /// The sports offered as one tap. `manual-workout` refuses a sport outside its activity types (run, ride/bike, swim, strength, walk, hiit, cardio, ...), so every chip is one it accepts.
    static let sports = ["Run", "Bike", "Swim", "Strength", "HIIT", "Cardio"]

    /// `calendar-edit` takes a date at most this many days from today.
    static let maxDaysAway = 400

    /// Whole days from `from` to `to` (both `YYYY-MM-DD`).
    static func daysBetween(_ from: String, _ to: String) -> Int {
        Int((PFFormat.date(to).timeIntervalSince(PFFormat.date(from)) / 86_400).rounded())
    }

    /// A whole number in the text (surrounding spaces ignored), nil for anything else.
    static func whole(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    /// A decimal in the text; a comma is read as the decimal point (an iPhone set to a comma locale types one).
    static func decimal(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let number = Double(value), number.isFinite else { return nil }
        return number
    }

    /// `HH:MM`, 00:00 to 23:59.
    static func isClock(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return hour <= 23 && minute <= 59
    }
}

// MARK: Job inputs

extension PFJobInputs {
    /// `calendar-edit` with `edit`: only the fields that changed. At least one is needed; minutes 5 to 600, target RPE 1 to 10, a day
    /// within 400 days of today; a template is a key from the web's swap list (<= 80 characters of letters, digits and `_ . : -`).
    static func calendarEdit(sessionID id: String?, newDate: String? = nil, minutes: Int? = nil, targetRPE: Int? = nil,
                             template: String? = nil) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        var inputs: [String: Any] = ["session_id": id, "action": "edit"]
        if let newDate {
            guard isDay(newDate) else { return nil }
            inputs["new_date"] = newDate
        }
        if let minutes {
            guard (5...600).contains(minutes) else { return nil }
            inputs["minutes"] = minutes
        }
        if let targetRPE {
            guard (1...10).contains(targetRPE) else { return nil }
            inputs["target_rpe"] = targetRPE
        }
        if let template {
            guard sessionID(template) != nil else { return nil }
            inputs["template"] = template
        }
        return inputs.count > 2 ? inputs : nil
    }

    /// `manual-workout-delete`: the logged workout's id.
    static func manualWorkoutDelete(id: String?) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        return ["id": id]
    }

    /// `manual-workout-edit`: the id and the fields that changed (a cleared optional goes as null).
    static func manualWorkoutEdit(id: String?, changes: [String: Any]) -> [String: Any]? {
        guard let id = sessionID(id), !changes.isEmpty else { return nil }
        var inputs = changes
        inputs["id"] = id
        return inputs
    }

    /// `manual-workout-comment`: a note added to a logged workout afterwards. The text is 1 to 2000 characters once trimmed; the server re-queues
    /// the Coach's reassessment.
    static func manualWorkoutComment(id: String?, text: String) -> [String: Any]? {
        guard let id = sessionID(id), PFManualWorkoutComments.problem(text: text, existing: 0) == nil else { return nil }
        return ["id": id, "text": text.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}

// MARK: Edit a planned session

/// The details form of one planned session: its day, minutes and target RPE as the athlete typed them. A blank minutes or RPE leaves
/// that field as it is.
struct PFSessionEditDraft: Equatable {
    let originalDate: String
    let originalMinutes: Int?
    let originalRPE: Int?
    var date: String
    var minutesText: String
    var rpeText: String

    init(date: String, minutes: Int?, rpe: Int?) {
        originalDate = date
        originalMinutes = minutes
        originalRPE = rpe
        self.date = date
        minutesText = minutes.map(String.init) ?? ""
        rpeText = rpe.map(String.init) ?? ""
    }

    private var minutes: Int? { PFManualPlan.whole(minutesText) }
    private var rpe: Int? { PFManualPlan.whole(rpeText) }
    private var wantsMinutes: Bool { !minutesText.trimmingCharacters(in: .whitespaces).isEmpty }
    private var wantsRPE: Bool { !rpeText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The minutes the form asks for when they differ from the session's.
    private var changedMinutes: Int? { wantsMinutes && minutes != originalMinutes ? minutes : nil }
    private var changedRPE: Int? { wantsRPE && rpe != originalRPE ? rpe : nil }
    private var changedDate: String? { date != originalDate ? date : nil }

    var hasChanges: Bool { changedDate != nil || changedMinutes != nil || changedRPE != nil }

    /// The sentence that says what is wrong with the form, or nil when it can be sent.
    func problem(today: String) -> String? {
        if !PFJobInputs.isDay(date) { return "Pick a day." }
        if abs(PFManualPlan.daysBetween(today, date)) > PFManualPlan.maxDaysAway { return "That day is more than 400 days away." }
        if wantsMinutes, !(minutes.map { (5...600).contains($0) } ?? false) { return "Minutes must be a whole number from 5 to 600." }
        if wantsRPE, !(rpe.map { (1...10).contains($0) } ?? false) { return "Effort must be a whole number from 1 to 10." }
        if !hasChanges { return "Nothing has changed." }
        return nil
    }

    /// The `calendar-edit` inputs: the changed fields only. nil when the form has a problem.
    func inputs(sessionID: String?, today: String) -> [String: Any]? {
        guard problem(today: today) == nil else { return nil }
        return PFJobInputs.calendarEdit(sessionID: sessionID, newDate: changedDate, minutes: changedMinutes, targetRPE: changedRPE)
    }
}

// MARK: Add a planned session

/// The form that books one session on the plan (`add-session`).
struct PFAddSessionDraft: Equatable {
    var date: String
    var sport = "Run"
    var minutesText = "45"
    var name = ""
    /// What the workout is, in the athlete's words (`description`, optional, up to 4000 characters, line breaks kept).
    var descriptionText = ""
    /// 1 books it once; more books it again every week.
    var repeatWeeks = 1

    init(date: String) { self.date = date }

    static let maxNameLength = 120
    static let repeatRange = 1...52

    private var minutes: Int? { PFManualPlan.whole(minutesText) }
    private var sportName: String { sport.trimmingCharacters(in: .whitespacesAndNewlines) }

    func problem(today: String) -> String? {
        if !PFJobInputs.isDay(date) { return "Pick a day." }
        if abs(PFManualPlan.daysBetween(today, date)) > PFManualPlan.maxDaysAway { return "That day is more than 400 days away." }
        if sportName.isEmpty { return "Say what sport it is." }
        if !(minutes.map { (5...480).contains($0) } ?? false) { return "Minutes must be a whole number from 5 to 480." }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxNameLength { return "The name is too long (120 characters at most)." }
        if !Self.repeatRange.contains(repeatWeeks) { return "Repeat for 1 to 52 weeks." }
        if PFSessionDescription.length(PFSessionDescription.normalized(descriptionText)) > PFSessionDescription.maxLength {
            return "The description is too long (4000 characters at most)."
        }
        return nil
    }

    /// The `add-session` inputs. `repeat_weeks` goes only when it is more than once, `description` only when something is written.
    func inputs(today: String) -> [String: Any]? {
        guard problem(today: today) == nil, let minutes else { return nil }
        var inputs: [String: Any] = ["date": date, "sport": sportName, "minutes": minutes]
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { inputs["name"] = title }
        let written = PFSessionDescription.normalized(descriptionText)
        if !written.isEmpty { inputs["description"] = written }
        if repeatWeeks > 1 { inputs["repeat_weeks"] = repeatWeeks }
        return inputs
    }
}

// MARK: A workout logged by hand

/// One dated comment on a logged workout (`comments[]` of `GET manual-workouts`: `{ts, text}`).
struct PFManualWorkoutComment: Equatable {
    /// The server's timestamp as text (ISO-8601); a number of seconds or milliseconds is turned into one.
    let ts: String
    let text: String

    /// "12 Mar 07:30", or just the day when the clock is unreadable, or "" when the stamp is.
    var whenText: String {
        guard ts.count >= 10, PFJobInputs.isDay(String(ts.prefix(10))) else { return "" }
        let day = PFFormat.shortDate(ts)
        return PFFormat.timeOfDay(ts).map { "\(day) \($0)" } ?? day
    }
}

/// One workout the athlete logged himself, as `GET manual-workouts` lists it.
struct PFManualWorkout: Identifiable, Equatable {
    let id: String
    let date: String
    let startTime: String?
    let sport: String
    let minutes: Int
    let km: Double?
    let avgHR: Int?
    let maxHR: Int?
    let rpe: Int?
    let notes: String?
    let planSessionID: String?
    /// The longer account added later (`details`), the dated comments (`comments`) and whether the Coach has written it up (`analysed`; nil from a server that does not say).
    var details: String? = nil
    var comments: [PFManualWorkoutComment] = []
    var analysed: Bool? = nil

    /// The line under the row: whether the Coach has read the workout in its present state. nil when the server did not say.
    var reviewLine: String? {
        guard let analysed else { return nil }
        return analysed ? "Coach has reviewed this" : "Coach review pending"
    }
}

/// Comments on a logged workout: the server's limits and the sentences the app shows.
enum PFManualWorkoutComments {
    static let maxLength = 2000
    static let maxCount = 50
    static let maxDetailsLength = 2000
    static let sentNote = "Saved. The Coach is reading it again; the updated review appears on that day."
    static let partialNote = "Saved \u{2014} the Coach could not be reached yet, saving another comment retries."

    /// What is wrong with a comment about to be sent, or nil. `existing` is how many comments the workout already has.
    static func problem(text: String, existing: Int) -> String? {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if count == 0 { return "Write something first." }
        if count > maxLength { return "A comment is 2000 characters at most." }
        if existing >= maxCount { return "This workout already has 50 comments." }
        return nil
    }

    static func isManualID(_ id: String) -> Bool { id.hasPrefix("manual:") }

    /// The sentence for a `manual-workout-comment` result: the plain one, or the partial one when the comment was kept but the Coach could not be queued.
    static func note(for result: PFJ) -> String {
        result["partial"].bool == true ? partialNote : sentNote
    }

    /// Comments in the order served, a timestamp read as ISO text or as epoch seconds / milliseconds; entries without text are left out.
    static func parse(_ comments: PFJ) -> [PFManualWorkoutComment] {
        comments.array.compactMap { row in
            guard let text = row["text"].text else { return nil }
            return PFManualWorkoutComment(ts: stamp(row["ts"]), text: text)
        }
    }

    private static func stamp(_ value: PFJ) -> String {
        if let text = value.string { return text }
        guard let number = value.double, number.isFinite, number > 0 else { return "" }
        let seconds = number > 1e11 ? number / 1000 : number
        return PFFormat.isoPlain.string(from: Date(timeIntervalSince1970: seconds))
    }
}

/// The small "Add details / comment" form for one logged workout. Codable so what was typed can stay on the phone until the server takes it.
struct PFManualWorkoutCommentDraft: Codable, Equatable {
    var id: String
    var text = ""

    func problem(existing: Int) -> String? { PFManualWorkoutComments.problem(text: text, existing: existing) }

    /// The `manual-workout-comment` inputs. nil when the text or the count is not acceptable.
    func inputs(existing: Int) -> [String: Any]? {
        guard problem(existing: existing) == nil else { return nil }
        return PFJobInputs.manualWorkoutComment(id: id, text: text)
    }
}

enum PFManualWorkouts {
    /// The list from the document: a bare array, or an object holding it under `workouts`, `manual_workouts` or `items`. Deleted entries
    /// and entries without an id, a day, a sport or minutes are left out; newest first.
    static func parse(_ data: Data?) -> [PFManualWorkout] {
        let root = PFJ(data: data)
        var rows = root.array
        if rows.isEmpty {
            for key in ["workouts", "manual_workouts", "items"] where !root[key].array.isEmpty {
                rows = root[key].array
                break
            }
        }
        let parsed: [PFManualWorkout] = rows.compactMap { row in
            if row["deleted"].bool == true { return nil }
            guard let id = row["id"].text, let date = row["date"].text, let sport = row["sport"].text,
                  let minutes = row["minutes"].int else { return nil }
            return PFManualWorkout(id: id, date: date, startTime: row["start_time"].text, sport: sport, minutes: minutes,
                                   km: row["km"].double, avgHR: row["avg_hr"].int, maxHR: row["max_hr"].int,
                                   rpe: row["rpe"].int, notes: row["notes"].text, planSessionID: row["plan_session_id"].text,
                                   details: row["details"].text, comments: PFManualWorkoutComments.parse(row["comments"]),
                                   analysed: row["analysed"].bool)
        }
        return parsed.sorted { ($0.date, $0.startTime ?? "") > ($1.date, $1.startTime ?? "") }
    }
}

/// The "Log a workout" form: every field as typed, so a failed send leaves it whole. Codable so it can be kept on the phone.
struct PFManualWorkoutDraft: Codable, Equatable {
    var date: String
    var startTime = ""
    var sport = "Run"
    var minutesText = ""
    var kmText = ""
    var avgHRText = ""
    var maxHRText = ""
    var rpeText = ""
    var notes = ""
    var planSessionID: String?
    /// The longer account (`details`, up to 2000 characters). Optional so a draft kept on the phone before this field existed still reads back.
    var details: String?

    static let maxNotesLength = 500

    /// The details field as a form binding: blank reads and writes as no details.
    var detailsText: String {
        get { details ?? "" }
        set { details = newValue.isEmpty ? nil : newValue }
    }

    init(date: String) { self.date = date }

    /// The form filled from a logged workout, to change it.
    init(editing workout: PFManualWorkout) {
        date = workout.date
        startTime = workout.startTime ?? ""
        sport = workout.sport
        minutesText = String(workout.minutes)
        kmText = workout.km.map { String($0) } ?? ""
        avgHRText = workout.avgHR.map(String.init) ?? ""
        maxHRText = workout.maxHR.map(String.init) ?? ""
        rpeText = workout.rpe.map(String.init) ?? ""
        notes = workout.notes ?? ""
        planSessionID = workout.planSessionID
        details = workout.details
    }

    private func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    private var sportName: String { sport.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var noteText: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var detailsTrimmed: String { detailsText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The sentence that says what is wrong with the form, or nil when it can be sent. A workout cannot be on a day that has not come.
    func problem(today: String) -> String? {
        if !PFJobInputs.isDay(date) { return "Pick a day." }
        if date > today { return "A workout you did cannot be in the future." }
        if !isBlank(startTime), !PFManualPlan.isClock(startTime.trimmingCharacters(in: .whitespaces)) { return "Start time must look like 07:30." }
        if sportName.isEmpty { return "Say what sport it was." }
        if !(PFManualPlan.whole(minutesText).map { (1...600).contains($0) } ?? false) { return "Minutes must be a whole number from 1 to 600." }
        if !isBlank(kmText), !(PFManualPlan.decimal(kmText).map { $0 > 0 && $0 <= 500 } ?? false) { return "Distance must be more than 0 and up to 500 km." }
        if !isBlank(avgHRText), !(PFManualPlan.whole(avgHRText).map { (30...230).contains($0) } ?? false) { return "Average heart rate must be 30 to 230." }
        if !isBlank(maxHRText), !(PFManualPlan.whole(maxHRText).map { (30...230).contains($0) } ?? false) { return "Max heart rate must be 30 to 230." }
        if let avg = PFManualPlan.whole(avgHRText), let top = PFManualPlan.whole(maxHRText), top < avg { return "Max heart rate cannot be below the average." }
        if !isBlank(rpeText), !(PFManualPlan.whole(rpeText).map { (1...10).contains($0) } ?? false) { return "Effort must be a whole number from 1 to 10." }
        if noteText.count > Self.maxNotesLength { return "Notes are too long (500 characters at most)." }
        if detailsTrimmed.count > PFManualWorkoutComments.maxDetailsLength { return "Details are too long (2000 characters at most)." }
        if let planSessionID, PFJobInputs.sessionID(planSessionID) == nil { return "That planned session cannot be linked." }
        return nil
    }

    /// The `manual-workout` inputs. Optional fields that are blank are left out. nil when the form has a problem.
    func inputs(today: String) -> [String: Any]? {
        guard problem(today: today) == nil, let minutes = PFManualPlan.whole(minutesText) else { return nil }
        var inputs: [String: Any] = ["date": date, "sport": sportName, "minutes": minutes]
        if !isBlank(startTime) { inputs["start_time"] = startTime.trimmingCharacters(in: .whitespaces) }
        if let km = PFManualPlan.decimal(kmText), !isBlank(kmText) { inputs["km"] = km }
        if let avg = PFManualPlan.whole(avgHRText) { inputs["avg_hr"] = avg }
        if let top = PFManualPlan.whole(maxHRText) { inputs["max_hr"] = top }
        if let rpe = PFManualPlan.whole(rpeText) { inputs["rpe"] = rpe }
        if !noteText.isEmpty { inputs["notes"] = noteText }
        if !detailsTrimmed.isEmpty { inputs["details"] = detailsTrimmed }
        if let planSessionID { inputs["plan_session_id"] = planSessionID }
        return inputs
    }

    /// The `manual-workout-edit` inputs: only what differs from the saved workout, a field cleared in the form as null. nil when the form
    /// has a problem or nothing differs.
    func editInputs(from saved: PFManualWorkout, today: String) -> [String: Any]? {
        guard let now = inputs(today: today) else { return nil }
        let before = PFManualWorkoutDraft(editing: saved)
        guard let was = before.inputs(today: "9999-12-31") else { return nil }
        var changes: [String: Any] = [:]
        for key in ["date", "start_time", "sport", "minutes", "km", "avg_hr", "max_hr", "rpe", "notes", "details", "plan_session_id"] {
            let new = now[key], old = was[key]
            if new == nil, old != nil {
                changes[key] = NSNull()
            } else if let new, !Self.same(new, old) {
                changes[key] = new
            }
        }
        return PFJobInputs.manualWorkoutEdit(id: saved.id, changes: changes)
    }

    private static func same(_ a: Any, _ b: Any?) -> Bool {
        guard let b else { return false }
        return (["v": a] as NSDictionary).isEqual(["v": b] as NSDictionary)
    }
}

/// What happens to a typed form after its send: kept whole when the server did not take it, gone when it did.
enum PFDraftKeeping {
    static func afterSend<Draft>(_ draft: Draft, tookIt: Bool) -> Draft? { tookIt ? nil : draft }

    static func encode(_ draft: PFManualWorkoutDraft) -> Data? { try? JSONEncoder().encode(draft) }

    static func decode(_ data: Data?) -> PFManualWorkoutDraft? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PFManualWorkoutDraft.self, from: data)
    }
}

// MARK: "Also send to Coach" from the phone's own Add Workout sheet

extension PFManualPlan {
    /// The `manual-workout` sport (one of `sports`) for the name typed or picked in the phone's own sheet ("Running", "Cycling", "Weightlifting"),
    /// or nil for a sport the server's activity types do not cover. Never guessed beyond these families.
    static func coachSport(forPhoneSport name: String) -> String? {
        let text = name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["hiit", "interval training"]) { return "HIIT" }
        if has(["strength", "weight", "lifting", "gym"]) { return "Strength" }
        if has(["run", "jog"]) { return "Run" }
        if has(["cycl", "bike", "biking", "ride"]) { return "Bike" }
        if has(["swim"]) { return "Swim" }
        if has(["cardio", "elliptical", "rowing"]) { return "Cardio" }
        return nil
    }
}

extension PFManualWorkoutDraft {
    /// The form filled from a workout just saved on the phone, so `inputs(today:)` is the one payload builder. nil when Coach cannot read it:
    /// a sport the server does not take, or a length outside 1 to 600 whole minutes. An optional number the server would refuse (a distance not
    /// above 0 or over 500 km, a heart rate outside 30 to 230) is left out instead of losing the workout.
    init?(savedOnPhone sport: String, start: Date, end: Date, distanceKm: Double?, avgHR: Int?, timeZone: TimeZone = .current) {
        guard let coachSport = PFManualPlan.coachSport(forPhoneSport: sport) else { return nil }
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        guard (1...600).contains(minutes) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.init(date: formatter.string(from: start))
        formatter.dateFormat = "HH:mm"
        startTime = formatter.string(from: start)
        self.sport = coachSport
        minutesText = String(minutes)
        if let distanceKm, distanceKm > 0, distanceKm <= 500 { kmText = String(format: "%.2f", distanceKm) }
        if let avgHR, (30...230).contains(avgHR) { avgHRText = String(avgHR) }
    }
}
