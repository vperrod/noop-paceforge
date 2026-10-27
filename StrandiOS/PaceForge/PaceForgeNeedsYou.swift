import Foundation

// "Needs you": everything PaceForge is waiting on the athlete for (a held treadmill run, an effort rating, a plan
// proposal, a critical question, today's feel), read from `needs_you` in /api/state (or /data/needs-you.json) and answered with
// POST /app/answer. This file is Foundation-only: the parsing, the checks before a request goes out and how the
// server's answer reads. It runs in the snapshot build and the answer handler, both off the main thread.

struct PFTreadmillBlock: Equatable {
    var reps: Int
    var speedKmh: Double
    var distM: Double?
    var durS: Double?
}

/// His newest confirmed belt answer, for "Same as last treadmill run".
struct PFTreadmillLast: Equatable {
    var speedKmh: Double?
    var inclinePct: Double?
    var blocks: [PFTreadmillBlock] = []
    var restKmh: Double?

    var isUsable: Bool { speedKmh != nil || !blocks.isEmpty }
}

struct PFTreadmillRun: Equatable {
    var name: String?
    var durationMin: Int
    var structured: Bool
    var last: PFTreadmillLast?
    var speedKmh: ClosedRange<Double> = 4...22
    var paceSecPerKm: ClosedRange<Double> = 164...900
    var inclinePct: ClosedRange<Double> = 0...15
}

/// One tap-answer of a critical question: the words on the button and the value the server stores.
struct PFQuestionOption: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String { value }
}

struct PFNeedsItem: Equatable, Identifiable {
    enum Kind: String {
        case treadmillPace = "treadmill_pace"
        case rpe
        case proposal
        case question
        case feel
    }

    var id: String
    var kind: Kind
    var title: String
    var meaning: String?
    var activityID: String?
    var sessionID: String?
    var proposalID: String?
    /// A critical question: its id (the server's, without the "question:" prefix of the item id) and the options one tap answers with.
    var questionID: String?
    var options: [PFQuestionOption] = []
    /// The day a feel answer is for; nil answers for today.
    var feelDate: String?
    var run: PFTreadmillRun?
}

/// One answer, in the shapes `POST /app/answer` takes.
enum PFNeedsAnswer {
    case treadmillSpeed(activityID: String, kmh: Double, inclinePct: Double?)
    case treadmillPace(activityID: String, secPerKm: Int, inclinePct: Double?)
    case sameAsLast(activityID: String, last: PFTreadmillLast, preferBlocks: Bool)
    case treadmillUnknown(activityID: String)
    case proposal(id: String, accept: Bool)
    case question(id: String, value: String)
    case questionDismiss(id: String)
    case feel(Int, date: String?)
    case rpe(Int, activityID: String?, sessionID: String?)

    /// The JSON body without the idempotency `key`.
    var body: [String: Any] {
        switch self {
        case .treadmillSpeed(let id, let kmh, let incline):
            return Self.with(["kind": "treadmill_pace", "activity_id": id, "speed_kmh": kmh], incline: incline)
        case .treadmillPace(let id, let sec, let incline):
            return Self.with(["kind": "treadmill_pace", "activity_id": id, "pace_s_per_km": sec], incline: incline)
        case .sameAsLast(let id, let last, let preferBlocks):
            var out: [String: Any] = ["kind": "treadmill_pace", "activity_id": id]
            if (preferBlocks || last.speedKmh == nil), !last.blocks.isEmpty {
                out["blocks"] = last.blocks.map { block -> [String: Any] in
                    var row: [String: Any] = ["reps": block.reps, "speed_kmh": block.speedKmh]
                    if let dist = block.distM { row["dist_m"] = dist }
                    if let dur = block.durS, block.distM == nil { row["dur_s"] = dur }
                    return row
                }
                if let rest = last.restKmh { out["rest_kmh"] = rest }
            } else if let speed = last.speedKmh {
                out["speed_kmh"] = speed
            }
            return Self.with(out, incline: last.inclinePct)
        case .treadmillUnknown(let id):
            return ["kind": "treadmill_pace_unknown", "activity_id": id]
        case .proposal(let id, let accept):
            return ["kind": "proposal", "id": id, "decision": accept ? "accept" : "dismiss"]
        case .question(let id, let value):
            return ["kind": "question", "id": id, "value": value]
        case .questionDismiss(let id):
            return ["kind": "question", "id": id, "decision": "dismiss"]
        case .feel(let value, let date):
            var out: [String: Any] = ["kind": "feel", "feel": value]
            if let date { out["date"] = date }
            return out
        case .rpe(let value, let activityID, let sessionID):
            var out: [String: Any] = ["kind": "rpe", "rpe": value]
            // Exactly one id, the activity's when the question has one.
            if let activityID { out["activity_id"] = activityID } else if let sessionID { out["session_id"] = sessionID }
            return out
        }
    }

    private static func with(_ base: [String: Any], incline: Double?) -> [String: Any] {
        var out = base
        if let incline { out["incline_pct"] = incline }
        return out
    }

    /// The same answer always has the same signature, so a retry after a lost reply reuses its idempotency key.
    func signature(for itemID: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return itemID + "|" + String(decoding: data, as: UTF8.self)
    }
}

enum PFNeedsParse {
    /// The items of a needs-you document (`{items: [...]}`), in the server's order. Unknown kinds and items the server marks
    /// unavailable are left out; an item missing the id its answer needs is left out too.
    static func items(_ doc: PFJ) -> [PFNeedsItem] {
        doc["items"].array.compactMap(item)
    }

    private static func item(_ j: PFJ) -> PFNeedsItem? {
        guard j["available"].bool != false,
              let id = j["id"].text,
              let kind = j["kind"].text.flatMap(PFNeedsItem.Kind.init(rawValue:)) else { return nil }
        let ref = j["ref"], metric = j["metric"]
        var out = PFNeedsItem(id: id, kind: kind, title: j["title"].text ?? "Needs you", meaning: j["meaning"].text)
        switch kind {
        case .treadmillPace:
            guard let activity = (ref["activity_id"].idString ?? metric["activity_id"].idString) else { return nil }
            out.activityID = activity
            out.run = run(metric)
        case .rpe:
            out.activityID = ref["activity_id"].idString
            out.sessionID = ref["session_id"].idString ?? metric["session_id"].idString
            if out.activityID == nil && out.sessionID == nil { return nil }
        case .proposal:
            guard let proposal = ref["id"].text ?? metric["proposal_id"].text else { return nil }
            out.proposalID = proposal
        case .question:
            guard let question = ref["id"].text else { return nil }
            out.questionID = question
            out.options = j["actions"].array.compactMap(option)
        case .feel:
            out.feelDate = metric["date"].text
        }
        return out
    }

    /// An action that carries a `value` is an answer; the Dismiss action has none and the card always offers Dismiss itself.
    private static func option(_ action: PFJ) -> PFQuestionOption? {
        guard let label = action["label"].text, let value = action["value"].text else { return nil }
        return PFQuestionOption(label: label, value: value)
    }

    private static func run(_ m: PFJ) -> PFTreadmillRun {
        var out = PFTreadmillRun(name: m["name"].text, durationMin: m["duration_min"].int ?? 0,
                                 structured: m["structured"].bool ?? false, last: last(m["last"]))
        let limits = m["limits"]
        if let r = range(limits["speed_kmh"]) { out.speedKmh = r }
        if let r = range(limits["pace_s_per_km"]) { out.paceSecPerKm = r }
        if let r = range(limits["incline_pct"]) { out.inclinePct = r }
        return out
    }

    private static func range(_ j: PFJ) -> ClosedRange<Double>? {
        let pair = j.array
        guard pair.count == 2, let lo = pair[0].double, let hi = pair[1].double, lo <= hi else { return nil }
        return lo...hi
    }

    private static func last(_ j: PFJ) -> PFTreadmillLast? {
        guard j.exists else { return nil }
        let blocks = j["blocks"].array.compactMap { b -> PFTreadmillBlock? in
            guard let reps = b["reps"].int, let speed = b["speed_kmh"].double,
                  b["dist_m"].double != nil || b["dur_s"].double != nil else { return nil }
            return PFTreadmillBlock(reps: reps, speedKmh: speed, distM: b["dist_m"].double, durS: b["dur_s"].double)
        }
        let out = PFTreadmillLast(speedKmh: j["speed_kmh"].double, inclinePct: j["incline_pct"].double,
                                  blocks: blocks, restKmh: j["rest_kmh"].double)
        return out.isUsable ? out : nil
    }
}

/// What he typed for a treadmill run, checked against the server's own limits before anything is sent.
enum PFTreadmillInput {
    struct Result {
        var answer: PFNeedsAnswer?
        /// Why Save is off, shown under the fields once he has typed something; nil when it is simply empty or fine.
        var hint: String?
    }

    static func check(run: PFTreadmillRun, activityID: String, useKmh: Bool, value: String, incline: String) -> Result {
        let typed = value.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return Result(answer: nil, hint: nil) }
        var inclinePct: Double?
        let inclineText = incline.trimmingCharacters(in: .whitespaces)
        if !inclineText.isEmpty {
            guard let n = number(inclineText), run.inclinePct.contains(n) else {
                return Result(answer: nil, hint: "Incline is \(format(run.inclinePct.lowerBound)) to \(format(run.inclinePct.upperBound)) %.")
            }
            inclinePct = n
        }
        if useKmh {
            guard let kmh = number(typed), run.speedKmh.contains(kmh) else {
                return Result(answer: nil, hint: "Speed is \(format(run.speedKmh.lowerBound)) to \(format(run.speedKmh.upperBound)) km/h.")
            }
            return Result(answer: .treadmillSpeed(activityID: activityID, kmh: kmh, inclinePct: inclinePct), hint: nil)
        }
        guard let sec = paceSeconds(typed), run.paceSecPerKm.contains(Double(sec)) else {
            return Result(answer: nil, hint: "Pace is m:ss per km, from \(clock(run.paceSecPerKm.lowerBound)) to \(clock(run.paceSecPerKm.upperBound)).")
        }
        return Result(answer: .treadmillPace(activityID: activityID, secPerKm: sec, inclinePct: inclinePct), hint: nil)
    }

    /// "5:10" is 310 s, "5" is 300 s. Anything else is not a pace.
    static func paceSeconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        guard parts.count == 2 else { return minutes * 60 }
        guard parts[1].count == 2, let seconds = Int(parts[1]), seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }

    /// A decimal number with a dot or a comma; nothing else (no exponent, no sign).
    static func number(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber || $0 == "." }), t.filter({ $0 == "." }).count <= 1,
              let n = Double(t), n.isFinite else { return nil }
        return n
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func clock(_ sec: Double) -> String {
        let total = Int(sec)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

/// How the server's answer to `POST /app/answer` reads.
struct PFAnswerOutcome: Equatable {
    var isSaved: Bool
    var message: String
    /// The fresh list the server sent back; nil when the reply carried none.
    var fresh: [PFNeedsItem]?

    static let unreachable = PFAnswerOutcome(isSaved: false, message: "Couldn't reach PaceForge. Nothing was changed, try again.", fresh: nil)

    static func from(status: Int, data: Data) -> PFAnswerOutcome {
        let body = PFJ(data: data)
        let server = body["message"].text
        guard (200..<300).contains(status) else {
            let fallback: String
            switch status {
            case 401: fallback = "PaceForge refused the sync token. Check it in Settings."
            case 404: fallback = "That is no longer waiting for you."
            case 429: fallback = "Too many answers this hour. Try again later."
            default: fallback = "Couldn't save that. Nothing was changed, try again."
            }
            return PFAnswerOutcome(isSaved: false, message: server ?? fallback, fresh: nil)
        }
        let list = body["needs_you"]
        return PFAnswerOutcome(isSaved: true, message: server ?? "Saved.", fresh: list.exists ? PFNeedsParse.items(list) : nil)
    }
}
