import Foundation

// Editing a recorded activity without ever touching the recording: relabel (walk, not run), trim, split, group, ungroup, and undo. The server keeps
// the edits as an append-only overlay (`data/activity-edits.json`); a change is PROPOSED with a before/after preview and only a Confirm applies it.
// Foundation only, so it is compiled into the macOS unit-test bundle.
//
// Jobs: `activity-edit-propose`, `activity-edit-confirm`, `activity-edit-reject`, `activity-edit-undo` (PaceForgeJob.swift). Reads: `GET api/activity-edits`
// (the history and the proposals). Contract: "Activity edit overlays" in docs/app-job-contract.md.

/// The five kinds of edit. Raw values are the contract's `op`.
enum PFActivityEditOp: String, Equatable, CaseIterable {
    case relabel
    case trim
    case split
    case group
    case ungroup

    var title: String {
        switch self {
        case .relabel: return "Change the sport"
        case .trim: return "Trim"
        case .split: return "Split in two"
        case .group: return "Group with others"
        case .ungroup: return "Ungroup"
        }
    }
}

/// One option of a closed list: the server's key and the words the app shows.
struct PFChoice: Identifiable, Equatable {
    let key: String
    let label: String
    var id: String { key }

    static func list(_ pairs: [(String, String)]) -> [PFChoice] { pairs.map { PFChoice(key: $0.0, label: $0.1) } }
}

enum PFActivityEditRules {
    /// The sports a recording can be relabelled as: the server's closed list (anything else is refused), with the words the app shows.
    static let relabelTypes: [PFChoice] = PFChoice.list([
        ("walking", "Walk"), ("hiking", "Hike"), ("running", "Run"), ("treadmill_running", "Treadmill run"),
        ("trail_running", "Trail run"), ("track_running", "Track run"), ("cycling", "Ride"), ("indoor_cycling", "Indoor ride"),
        ("lap_swimming", "Pool swim"), ("open_water_swimming", "Open-water swim"), ("strength_training", "Strength"),
        ("hiit", "HIIT"), ("cardio", "Cardio"), ("yoga", "Yoga"), ("rowing", "Rowing"), ("elliptical", "Elliptical"), ("other", "Other"),
    ])

    /// Each part of a trim or a split is at least this long.
    static let minPartSeconds = 10.0
    /// Seconds from the start of the recording, at most two days.
    static let maxSeconds = 172_800.0
    static let maxGroup = 10
    static let maxNameLength = 80
    static let maxRationaleLength = 400

    static func label(forType key: String?) -> String? {
        guard let key else { return nil }
        let lower = key.lowercased()
        return relabelTypes.first { $0.key == lower }?.label ?? PFFormat.capitalized(PFFormat.words(lower))
    }

    /// A recording id as the server's validator takes it: a whole number from 1, below 10^15. The app keeps ids as text; the job wants a number.
    static func recordingID(_ id: String?) -> Int? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty, id.count <= 15,
              id.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(id), value >= 1 else { return nil }
        return value
    }

    /// A proposal or edit id: 32 lowercase hex characters.
    static func hexID(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), id.count == 32,
              id.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return id
    }

    /// Seconds from the start of the recording as the athlete types them: `12:30`, `1:02:03` or plain seconds (`750`). nil for anything else.
    static func seconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            let piece = String(part).replacingOccurrences(of: ",", with: ".")
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  let value = Double(piece), value.isFinite, value >= 0 else { return nil }
            // After the first field a colon-separated value is minutes or seconds.
            if parts.count > 1, index > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        return total <= maxSeconds ? total : nil
    }
}

// MARK: Job inputs

extension PFJobInputs {
    /// `activity-edit-propose`: the op's own fields plus an optional rationale. `op` is always sent (the server's validator requires it, the
    /// contract's table lists only the op's fields). Ids go as numbers. nil when the values could not pass the server's validator.
    static func activityEditPropose(_ op: PFActivityEditOp, activityID: String?, activityType: String? = nil, name: String? = nil,
                                    startS: Double? = nil, endS: Double? = nil, atS: Double? = nil, groupIDs: [String] = [],
                                    rationale: String = "") -> [String: Any]? {
        var inputs: [String: Any] = ["op": op.rawValue]
        if op == .group {
            let ids = groupIDs.compactMap { PFActivityEditRules.recordingID($0) }
            guard ids.count == groupIDs.count, (2...PFActivityEditRules.maxGroup).contains(ids.count), Set(ids).count == ids.count else { return nil }
            inputs["activity_ids"] = ids
        } else {
            guard let id = PFActivityEditRules.recordingID(activityID) else { return nil }
            inputs["activity_id"] = id
        }
        switch op {
        case .relabel:
            if let activityType {
                guard PFActivityEditRules.relabelTypes.contains(where: { $0.key == activityType }) else { return nil }
                inputs["activity_type"] = activityType
            }
            if let name {
                let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard (1...PFActivityEditRules.maxNameLength).contains(text.count) else { return nil }
                inputs["name"] = text
            }
            guard inputs["activity_type"] != nil || inputs["name"] != nil else { return nil }
        case .trim:
            if let startS {
                guard (0...PFActivityEditRules.maxSeconds).contains(startS) else { return nil }
                inputs["start_s"] = startS
            }
            if let endS {
                guard (0...PFActivityEditRules.maxSeconds).contains(endS) else { return nil }
                inputs["end_s"] = endS
            }
            guard inputs["start_s"] != nil || inputs["end_s"] != nil else { return nil }
        case .split:
            guard let atS, (0...PFActivityEditRules.maxSeconds).contains(atS) else { return nil }
            inputs["at_s"] = atS
        case .group, .ungroup:
            break
        }
        let why = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        if !why.isEmpty {
            guard why.count <= PFActivityEditRules.maxRationaleLength else { return nil }
            inputs["rationale"] = why
        }
        return inputs
    }

    /// `activity-edit-confirm`: the proposal's id, nothing else.
    static func activityEditConfirm(proposalID: String?) -> [String: Any]? {
        guard let id = PFActivityEditRules.hexID(proposalID) else { return nil }
        return ["proposal_id": id]
    }

    /// `activity-edit-reject`: the proposal's id and, when given, a reason of at most 200 characters.
    static func activityEditReject(proposalID: String?, reason: String = "") -> [String: Any]? {
        guard let id = PFActivityEditRules.hexID(proposalID) else { return nil }
        var inputs: [String: Any] = ["proposal_id": id]
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !why.isEmpty { inputs["reason"] = String(why.prefix(200)) }
        return inputs
    }

    /// `activity-edit-undo`: the id of an edit that is still in force.
    static func activityEditUndo(editID: String?) -> [String: Any]? {
        guard let id = PFActivityEditRules.hexID(editID) else { return nil }
        return ["edit_id": id]
    }
}

// MARK: The edit form

/// The form for one edit of one recording, as the athlete typed it. A failed send leaves it whole.
struct PFActivityEditDraft: Equatable {
    let activityID: String
    /// The recording's sport as it is now (Garmin's key), so a relabel to the same sport reads as no change.
    let currentType: String?
    let currentName: String?
    /// The recording's length in seconds when known, to check a trim or a split before it is sent.
    let durationS: Double?

    var op: PFActivityEditOp = .relabel
    var typeKey: String?
    var name = ""
    var startText = ""
    var endText = ""
    var splitText = ""
    /// The other recordings to group this one with.
    var groupWith: Set<String> = []
    var rationale = ""

    init(activityID: String, currentType: String?, currentName: String?, durationS: Double?) {
        self.activityID = activityID
        self.currentType = currentType
        self.currentName = currentName
        self.durationS = durationS
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The sentence that says what is wrong with the form, or nil when it can be sent.
    var problem: String? {
        if PFActivityEditRules.recordingID(activityID) == nil { return "This recording cannot be edited." }
        if rationale.trimmingCharacters(in: .whitespacesAndNewlines).count > PFActivityEditRules.maxRationaleLength {
            return "The note is too long (400 characters at most)."
        }
        let minimum = PFActivityEditRules.minPartSeconds
        switch op {
        case .relabel:
            if typeKey == nil && trimmedName.isEmpty { return "Pick a sport or write a new name." }
            if trimmedName.count > PFActivityEditRules.maxNameLength { return "The name is too long (80 characters at most)." }
            let sameType = typeKey == nil || typeKey == (currentType ?? "").lowercased()
            let sameName = trimmedName.isEmpty || trimmedName == (currentName ?? "")
            if sameType && sameName { return "Nothing has changed." }
        case .trim:
            if isBlank(startText) && isBlank(endText) { return "Give a start, an end or both." }
            var start: Double?
            var end: Double?
            if !isBlank(startText) {
                guard let value = PFActivityEditRules.seconds(startText) else { return "The start looks like 2:30 (minutes and seconds)." }
                start = value
            }
            if !isBlank(endText) {
                guard let value = PFActivityEditRules.seconds(endText) else { return "The end looks like 12:30 (minutes and seconds)." }
                end = value
            }
            let from = start ?? 0
            if let end, end - from < minimum { return "Keep at least 10 seconds." }
            if let durationS, start != nil || end != nil {
                let to = end ?? durationS
                if from >= durationS || to > durationS { return "That is outside the recording, which is \(PFFormat.clock(durationS)) long." }
                if to - from < minimum { return "Keep at least 10 seconds." }
                if from == 0 && to == durationS { return "That keeps the whole recording." }
            }
        case .split:
            guard let at = PFActivityEditRules.seconds(splitText) else { return "The split point looks like 6:00 (minutes and seconds)." }
            if at < minimum { return "Each part has to be at least 10 seconds." }
            if let durationS, at > durationS - minimum { return "Each part has to be at least 10 seconds, so split before \(PFFormat.clock(durationS - minimum))." }
        case .group:
            if groupWith.isEmpty { return "Pick at least one more recording." }
            if groupWith.count + 1 > PFActivityEditRules.maxGroup { return "A group holds at most 10 recordings." }
            if groupWith.contains(where: { PFActivityEditRules.recordingID($0) == nil }) { return "One of those recordings cannot be grouped." }
        case .ungroup:
            break
        }
        return nil
    }

    /// The `activity-edit-propose` inputs; nil when the form has a problem.
    var inputs: [String: Any]? {
        guard problem == nil else { return nil }
        switch op {
        case .relabel:
            // Only what changed goes: the same sport again is left out.
            let kind = typeKey == (currentType ?? "").lowercased() ? nil : typeKey
            let title = trimmedName.isEmpty || trimmedName == (currentName ?? "") ? nil : trimmedName
            return PFJobInputs.activityEditPropose(.relabel, activityID: activityID, activityType: kind, name: title, rationale: rationale)
        case .trim:
            return PFJobInputs.activityEditPropose(.trim, activityID: activityID,
                                                   startS: isBlank(startText) ? nil : PFActivityEditRules.seconds(startText),
                                                   endS: isBlank(endText) ? nil : PFActivityEditRules.seconds(endText), rationale: rationale)
        case .split:
            return PFJobInputs.activityEditPropose(.split, activityID: activityID, atS: PFActivityEditRules.seconds(splitText), rationale: rationale)
        case .group:
            return PFJobInputs.activityEditPropose(.group, activityID: activityID, groupIDs: [activityID] + groupWith.sorted(), rationale: rationale)
        case .ungroup:
            return PFJobInputs.activityEditPropose(.ungroup, activityID: activityID, rationale: rationale)
        }
    }
}

// MARK: What the server holds

/// One recording as a preview shows it, before or after an edit.
struct PFEditRow: Equatable, Identifiable {
    let id: String
    let name: String
    let type: String?
    let startTime: String?
    let durationS: Double?
    let distanceM: Double?
    let avgHr: Int?
    /// The figures the server could not work out for this span (`basis.unknown`): shown as unknown, never as a guess.
    let unknown: [String]

    var line: String {
        var parts: [String] = []
        if let type = PFActivityEditRules.label(forType: type) { parts.append(type) }
        if let durationS { parts.append(PFFormat.clock(durationS)) }
        if let distanceM, distanceM > 0 {
            parts.append(PFFormat.oneDecimal(distanceM / 1000) + " km")
        } else if unknown.contains("distance_meters") {
            parts.append("distance unknown")
        }
        if let avgHr {
            parts.append("avg \(avgHr) bpm")
        } else if unknown.contains("avg_hr") {
            parts.append("average heart rate unknown")
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

struct PFEditTotals: Equatable {
    let count: Int
    let durationS: Double
    let distanceM: Double

    var line: String {
        var text = count == 1 ? "1 recording" : "\(count) recordings"
        text += ", " + PFFormat.clock(durationS)
        if distanceM > 0 { text += ", " + PFFormat.oneDecimal(distanceM / 1000) + " km" }
        return text
    }
}

struct PFEditPreview: Equatable {
    var before: [PFEditRow] = []
    var after: [PFEditRow] = []
    var beforeTotals: PFEditTotals?
    var afterTotals: PFEditTotals?
}

/// What an edit does, as a proposal or a history record carries it.
struct PFEditSpec: Equatable {
    let op: String
    let activityID: String?
    let activityIDs: [String]
    let startS: Double?
    let endS: Double?
    let atS: Double?
    let activityType: String?
    let name: String?
    /// For an undo or an ungroup: the edit it switched off.
    let target: String?

    func touches(_ id: String) -> Bool { activityID == id || activityIDs.contains(id) }

    /// One sentence for the history and the proposal.
    var summary: String {
        switch op {
        case "relabel":
            var parts: [String] = []
            if let kind = PFActivityEditRules.label(forType: activityType) { parts.append("labelled as \(kind.lowercased())") }
            if let name { parts.append("renamed \u{201C}\(name)\u{201D}") }
            return PFFormat.capitalized(parts.isEmpty ? "relabelled" : parts.joined(separator: ", "))
        case "trim":
            let from = startS.map { PFFormat.clock($0) }
            let to = endS.map { PFFormat.clock($0) }
            if let from, let to { return "Trimmed to \(from) \u{2013} \(to)" }
            if let from { return "Trimmed to start at \(from)" }
            if let to { return "Trimmed to end at \(to)" }
            return "Trimmed"
        case "split":
            return atS.map { "Split at \(PFFormat.clock($0))" } ?? "Split in two"
        case "group":
            return "Grouped \(activityIDs.count) recordings"
        case "ungroup":
            return "Ungrouped"
        case "undo":
            return "Undid an earlier edit"
        default:
            return "Edited"
        }
    }
}

/// An edit that was applied (or undone later); the history lists these.
struct PFEditRecord: Equatable, Identifiable {
    let id: String
    let seq: Int
    let ts: String
    let author: String
    let source: String
    let spec: PFEditSpec
}

/// An edit that was proposed: nothing is applied until it is confirmed.
struct PFEditProposal: Equatable, Identifiable {
    let id: String
    /// pending, confirmed, rejected, stale or expired.
    let state: String
    let createdAt: String
    let author: String
    let source: String
    let rationale: String?
    let spec: PFEditSpec
    let preview: PFEditPreview

    var isPending: Bool { state == "pending" }
    var isFromCoach: Bool { author == "coach" || source == "coach" }
}

/// A recording as the edits left it (a group, a trim, a part): the Garmin recordings behind it and the edits it carries.
struct PFEditView: Equatable {
    let id: String
    /// recording, trim, part or group.
    let kind: String
    let sourceIDs: [String]
    let editIDs: [String]
}

/// `GET api/activity-edits`: the full history, the proposals (pending first) and which recordings are edited.
struct PFEditsDoc: Equatable {
    var edits: [PFEditRecord] = []
    var proposals: [PFEditProposal] = []
    /// For each edited view: the recordings behind it and the edits it carries.
    var views: [PFEditView] = []
    var skipped = 0

    /// The ids of edits an undo or an ungroup switched off.
    private var switchedOff: Set<String> {
        Set(edits.filter { $0.spec.op == "undo" || $0.spec.op == "ungroup" }.compactMap { $0.spec.target })
    }

    /// An edit still in force: not an undo or an ungroup record itself, and not switched off by one.
    func isActive(_ record: PFEditRecord) -> Bool {
        record.spec.op != "undo" && record.spec.op != "ungroup" && !switchedOff.contains(record.id)
    }

    /// The edits that concern this recording, oldest first: the ones that name it, the ones carried by a view it is part of, and the undo or
    /// ungroup records aimed at any of those.
    func history(for activityID: String) -> [PFEditRecord] {
        var mine = Set(edits.filter { $0.spec.touches(activityID) }.map { $0.id })
        for view in views where view.sourceIDs.contains(activityID) { mine.formUnion(view.editIDs) }
        let aimedAt = Set(edits.filter { $0.spec.target.map { mine.contains($0) } == true }.map { $0.id })
        mine.formUnion(aimedAt)
        return edits.filter { mine.contains($0.id) }.sorted { $0.seq < $1.seq }
    }

    /// Whether the recording is a group of several: the only kind that can be ungrouped.
    func isGroup(_ activityID: String) -> Bool {
        views.contains { $0.id == activityID && $0.kind == "group" }
    }

    /// The proposals that concern this recording, pending first.
    func proposals(for activityID: String) -> [PFEditProposal] {
        let mine = proposals.filter { $0.spec.touches(activityID) }
        return mine.filter { $0.isPending } + mine.filter { !$0.isPending }
    }
}

enum PFActivityEdits {
    static func spec(_ j: PFJ) -> PFEditSpec {
        PFEditSpec(op: j["op"].text ?? "", activityID: j["activity_id"].idString, activityIDs: j["activity_ids"].array.compactMap { $0.idString },
                   startS: j["start_s"].double, endS: j["end_s"].double, atS: j["at_s"].double, activityType: j["activity_type"].text,
                   name: j["name"].text, target: j["target"].text)
    }

    static func record(_ j: PFJ) -> PFEditRecord? {
        guard let id = j["id"].text, j["op"].text != nil else { return nil }
        return PFEditRecord(id: id, seq: j["seq"].int ?? 0, ts: j["ts"].text ?? "", author: j["author"].text ?? "athlete",
                            source: j["source"].text ?? "", spec: spec(j))
    }

    /// One recording of a preview. `basis` names the figures that could not be worked out.
    static func row(_ j: PFJ) -> PFEditRow? {
        guard let id = j["activity_id"].idString else { return nil }
        return PFEditRow(id: id, name: j["name"].text ?? "Recording", type: j["activity_type"].text, startTime: j["start_time"].text,
                         durationS: j["duration_seconds"].double, distanceM: j["distance_meters"].double, avgHr: j["avg_hr"].int,
                         unknown: j["basis"]["unknown"].strings)
    }

    private static func totals(_ j: PFJ) -> PFEditTotals? {
        guard j.exists, let count = j["count"].int else { return nil }
        return PFEditTotals(count: count, durationS: j["duration_seconds"].double ?? 0, distanceM: j["distance_meters"].double ?? 0)
    }

    static func preview(_ j: PFJ) -> PFEditPreview {
        PFEditPreview(before: j["before"].array.compactMap { row($0) }, after: j["after"].array.compactMap { row($0) },
                      beforeTotals: totals(j["totals"]["before"]), afterTotals: totals(j["totals"]["after"]))
    }

    /// A proposal, as the propose job returns it and as the document lists it.
    static func proposal(_ j: PFJ) -> PFEditProposal? {
        guard let id = j["id"].text, j["edit"].exists else { return nil }
        return PFEditProposal(id: id, state: j["state"].text ?? "pending", createdAt: j["created_at"].text ?? "", author: j["author"].text ?? "athlete",
                              source: j["source"].text ?? "", rationale: j["rationale"].text, spec: spec(j["edit"]), preview: preview(j["preview"]))
    }

    /// The document; an empty one when it is not readable.
    static func parse(_ data: Data?) -> PFEditsDoc {
        let root = PFJ(data: data)
        var doc = PFEditsDoc()
        doc.edits = root["edits"].array.compactMap { record($0) }
        doc.proposals = root["proposals"].array.compactMap { proposal($0) }
        doc.views = root["edited"].array.map { view in
            PFEditView(id: view["id"].idString ?? "", kind: view["kind"].text ?? "", sourceIDs: view["source_ids"].array.compactMap { $0.idString },
                       editIDs: view["edit_ids"].strings)
        }
        doc.skipped = root["skipped"].array.count
        return doc
    }
}
