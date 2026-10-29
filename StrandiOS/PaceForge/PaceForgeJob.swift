import Foundation

// The iPhone app's one door to PaceForge's write actions: `POST api/app/job` with `{"job": name, "inputs": {...}}`, then
// `GET api/app/job/<id>` for a job that does not finish at once. The contract is docs/app-job-contract.md on the server's
// parity/app-jobs branch; every field name below is that document's.
//
// This file is the pure half (Foundation only, so it is compiled into the macOS unit-test bundle): the job names, the request
// bodies, how a reply or a refusal reads, the polling schedule and how a workout photo's draft reads. The network half is
// PaceForgeJobClient.swift.

/// The jobs the app runs. Raw values are the contract's job names.
enum PFJobName: String, Equatable {
    case sync
    case analyzeWorkoutPhoto = "analyze-workout-photo"
    case saveRpe = "save-rpe"
    case adjustToday = "adjust-today"
    case coachFeedback = "coach-feedback"
    case coach

    /// How long a job is expected to take from the request to "done", in seconds, from the contract: a photo read is 5 s to about 4.5 min
    /// (the local vision model is shared), a Garmin sync about 8 s and a minute or more behind a Garmin rate limit, the rest run inline.
    var expectedSeconds: TimeInterval {
        switch self {
        case .analyzeWorkoutPhoto: return 270
        case .coach: return 300
        case .sync: return 120
        case .saveRpe, .adjustToday, .coachFeedback: return 30
        }
    }

    /// The request timeout. A photo body is up to a few hundred kilobytes of base64 over a mobile link; the other bodies are tiny.
    var requestTimeout: TimeInterval {
        self == .analyzeWorkoutPhoto ? 120 : 30
    }
}

/// The request body of `POST api/app/job`.
enum PFJobRequest {
    static func body(_ job: PFJobName, inputs: [String: Any] = [:]) -> [String: Any] {
        ["job": job.rawValue, "inputs": inputs]
    }
}

/// The `inputs` of each job, with the contract's field names. A builder returns nil when its values could not pass the
/// contract's own limits, so the app never sends a request it knows the server will refuse.
enum PFJobInputs {
    /// A Garmin activity id (digits) or a ride id (`bike:` and its date-time) as the server reads them. Anything else (a NOOP strap
    /// key, an empty text) is nil: the server would refuse it.
    static func activityID(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        if id.hasPrefix("bike:") { return id.count > "bike:".count ? id : nil }
        return id.allSatisfy { $0.isASCII && $0.isNumber } ? id : nil
    }

    /// A fresh photo id: the contract wants `[a-z0-9-]{8,64}`, and a lowercase UUID is that.
    static func newPhotoID() -> String { UUID().uuidString.lowercased() }

    /// `analyze-workout-photo`. The photo is bound to the activity when it has a usable id, else to the day (the server keys
    /// an unrecorded session by date); with neither it is sent unbound. `auto_attach` asks the server to attach the first-try
    /// reading to the session itself, unchecked: the athlete is never asked to confirm a photo.
    static func analyzeWorkoutPhoto(photoID: String, imageBase64: String, activityID: String?, date: String?) -> [String: Any] {
        var inputs: [String: Any] = ["photo_id": photoID, "image_base64": imageBase64, "auto_attach": true]
        if let id = Self.activityID(activityID) {
            inputs["activity_id"] = id
        } else if let date, !date.isEmpty {
            inputs["date"] = date
        }
        return inputs
    }

    /// `save-rpe`: `{"data": {rpe, activity_id | date}}`. The rating is 1 to 10; a session with no usable activity id needs its date.
    static func saveRpe(_ rpe: Int, activityID: String?, date: String?) -> [String: Any]? {
        guard (1...10).contains(rpe) else { return nil }
        var data: [String: Any] = ["rpe": rpe]
        if let id = Self.activityID(activityID) {
            data["activity_id"] = id
        } else if let date, !date.isEmpty {
            data["date"] = date
        } else {
            return nil
        }
        return ["data": data]
    }

    /// `adjust-today`: `{"mode": "tired" | "sick" | "time", "minutes": 15...240}`; minutes only goes with "time".
    static func adjustToday(_ mode: PFAdjustMode) -> [String: Any]? {
        switch mode {
        case .tired: return ["mode": "tired"]
        case .sick: return ["mode": "sick"]
        case .minutes(let minutes):
            guard (15...240).contains(minutes) else { return nil }
            return ["mode": "time", "minutes": minutes]
        }
    }

    /// `coach`: `{"instruction": text}`, 1 to 2000 characters. An order in plain words; a question goes to the chat instead.
    static func coach(_ instruction: String) -> [String: Any]? {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.unicodeScalars.count <= 2000 else { return nil }
        return ["instruction": text]
    }

    /// `coach-feedback`: `{"data": {target: {kind, id}, verdict, reason}}`. The reason is left out when empty (the server limit is 300).
    static func coachFeedback(kind: String, id: String, verdict: PFVerdict, reason: String = "") -> [String: Any] {
        var data: [String: Any] = ["target": ["kind": kind, "id": id], "verdict": verdict.rawValue]
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !why.isEmpty { data["reason"] = String(why.prefix(300)) }
        return ["data": data]
    }
}

/// What the Adjust today card can ask for (the web offers tired, sick and 30 / 45 / 60 minutes).
enum PFAdjustMode: Equatable {
    case tired
    case sick
    case minutes(Int)
}

/// A thumbs up or down on a piece of coaching.
enum PFVerdict: String, Equatable {
    case up
    case down
}

// MARK: Where a job stands

/// The state the server reports for a job. A state this app does not know reads as running, so the wait goes on until its time is up.
enum PFJobState: Equatable {
    case queued
    case running
    case done
    case failed

    init(_ text: String?) {
        switch text ?? "" {
        case "queued": self = .queued
        case "done": self = .done
        case "failed": self = .failed
        default: self = .running
        }
    }

    var isFinished: Bool { self == .done || self == .failed }
}

/// What a view shows about the job it started.
enum PFJobPhase: Equatable {
    case idle
    case sending
    case working
    case done
    case failed(String)
}

/// The reply to `POST api/app/job`. A fast job has run inline, so its `state` is done and `result` holds what it returned; a slow
/// one is queued and is followed by id.
struct PFJobSubmission {
    let id: String
    let state: PFJobState
    let result: PFJ
}

/// The reply to `GET api/app/job/<id>`.
struct PFJobStatus: Equatable {
    let state: PFJobState
    /// The first 300 characters of the runner's own failure line, when the job failed.
    let error: String?
}

// MARK: Errors

/// Why a job did not go through, in the words the app shows.
enum PFJobError: Error, Equatable {
    case offline
    case rateLimited(retryAfter: Int?)
    /// 403: "NOOP sync" is switched off in PaceForge's Settings.
    case syncOff
    /// 401, or the login page in place of JSON.
    case tokenNotAccepted
    /// 400, 404, 409 or 413, with the server's own plain-English reason when it gave one.
    case refused(String)
    case serverTrouble(Int)
    /// The job ran and ended in failure; carries the runner's line.
    case failed(String?)
    /// The app stopped waiting; the job may still finish on the server.
    case timedOut
    case cancelled
    case unreadable

    var message: String {
        switch self {
        case .offline:
            return "Couldn't reach PaceForge. Check your connection and try again."
        case .rateLimited(let retryAfter):
            return "That is a lot of requests for one hour. " + Self.waitText(retryAfter)
        case .syncOff:
            return "NOOP sync is off in PaceForge's Settings, so this iPhone cannot do that yet."
        case .tokenNotAccepted:
            return "PaceForge did not accept this iPhone's token. Check More \u{203A} PaceForge sync."
        case .refused(let text):
            return text
        case .serverTrouble(let code):
            return "PaceForge had a problem (HTTP \(code)). Try again later."
        case .failed(let line):
            guard let line, !line.isEmpty else { return "PaceForge could not finish that." }
            return "PaceForge could not finish that: \(line)"
        case .timedOut:
            return "PaceForge is taking longer than expected. It may still finish; check back in a few minutes."
        case .cancelled:
            return "Stopped."
        case .unreadable:
            return "PaceForge sent an answer this app does not understand."
        }
    }

    private static func waitText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Try again later." }
        if seconds <= 60 { return "Try again in a minute." }
        return "Try again in \((seconds + 59) / 60) min."
    }

    /// A request that threw: no connection, a timeout and every other transport failure read as offline.
    static func transport(_ error: Error) -> PFJobError {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError { return urlError.code == .cancelled ? .cancelled : .offline }
        return .refused(String(error.localizedDescription.prefix(200)))
    }
}

// MARK: Replies

enum PFJobReply {
    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }

    /// The error a status maps to, or nil for a 2xx. The body's `error` / `message` text is the server's reason for a refusal.
    static func error(status: Int, body: Data?, retryAfter: Int?) -> PFJobError? {
        if (200..<300).contains(status) {
            // Without a valid token the server answers 200 with its HTML login page.
            if body?.first(where: { !isSpace($0) }) == UInt8(ascii: "<") { return .tokenNotAccepted }
            return nil
        }
        switch status {
        case 401: return .tokenNotAccepted
        case 403: return .syncOff
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 400, 404, 409, 413:
            let json = PFJ(data: body)
            if let said = (json["error"].text ?? json["message"].text) { return .refused(String(said.prefix(300))) }
            switch status {
            case 413: return .refused("That was too big to send.")
            case 404: return .refused("PaceForge does not know that action. PaceForge may need updating.")
            case 409: return .refused("PaceForge could not do that right now.")
            default: return .refused("PaceForge did not accept that.")
            }
        default:
            return .serverTrouble(status)
        }
    }

    /// `POST api/app/job`: 200 with `{ok, job, id, state, result?}`. The id is digits only; it goes into a URL path.
    static func submission(status: Int, body: Data?, retryAfter: Int?) -> Result<PFJobSubmission, PFJobError> {
        if let failure = error(status: status, body: body, retryAfter: retryAfter) { return .failure(failure) }
        let json = PFJ(data: body)
        guard let id = json["id"].idString, !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return .failure(.unreadable)
        }
        return .success(PFJobSubmission(id: id, state: PFJobState(json["state"].string), result: json["result"]))
    }

    /// `GET api/app/job/<id>`: 200 with `{id, job, state, error, ...}`.
    static func status(status: Int, body: Data?, retryAfter: Int?) -> Result<PFJobStatus, PFJobError> {
        if let failure = error(status: status, body: body, retryAfter: retryAfter) { return .failure(failure) }
        let json = PFJ(data: body)
        guard json["state"].string != nil else { return .failure(.unreadable) }
        return .success(PFJobStatus(state: PFJobState(json["state"].string), error: json["error"].text))
    }
}

// MARK: Waiting

/// How the app follows a slow job: the first look after 2 s (the contract asks for no faster than that), then every 5 s, until the job's
/// expected time plus a margin has passed.
enum PFJobPolling {
    static let firstDelay: TimeInterval = 2
    static let laterDelay: TimeInterval = 5
    static let margin: TimeInterval = 60

    /// The wait before poll number `polls + 1`, given that `polls` have been made.
    static func delay(afterPolls polls: Int) -> TimeInterval { polls == 0 ? firstDelay : laterDelay }

    static func deadline(for job: PFJobName) -> TimeInterval { job.expectedSeconds + margin }

    static func shouldGiveUp(job: PFJobName, elapsed: TimeInterval) -> Bool { elapsed >= deadline(for: job) }
}

// MARK: Adjust today

enum PFAdjustToday {
    /// The line the card shows after the job: the server's `summary` when it changed the session, its `reason` when it did not.
    static func confirmation(_ result: PFJ) -> String {
        if result["adjusted"].bool == true, let summary = result["summary"].text { return String(summary.prefix(300)) }
        if let reason = result["reason"].text { return String(reason.prefix(300)) }
        return result["adjusted"].bool == true ? "Today's session is adjusted." : "Nothing changed."
    }
}

// MARK: Coach thumbs

enum PFCoachFeedback {
    static let storageKey = "pf.coachFeedback"

    /// The key a rating is kept under on the phone: the target's kind and id.
    static func key(kind: String, id: String) -> String { "\(kind):\(id)" }
}

// MARK: Tell the coach

/// What a finished `coach` instruction left behind. The job returns no text of its own: the reply lands in the shared chat transcript
/// and any change it asks for is filed as a proposal in Needs you.
enum PFCoachInstruction {
    /// The newest Coach reply in the transcript, when it is not the one that was there before the instruction was sent.
    static func reply(in chat: [PFChatTurn], after previousTS: String?) -> String? {
        guard let last = chat.last(where: { $0.role == "coach" }), last.ts != previousTS else { return nil }
        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(600))
    }

    /// The titles of the proposals that were not in Needs you before the instruction.
    static func newProposals(before: [PFNeedsItem], after: [PFNeedsItem]) -> [String] {
        let known = Set(before.map { $0.id })
        return after.filter { $0.kind == .proposal && !known.contains($0.id) }.map { $0.title }
    }
}
