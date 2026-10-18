import Foundation

/// How PaceForge's day-events.json refines the day My Day already has: a planned session gets its clock
/// time, a weigh-in its time, a niggle becomes a note. Pure and Foundation-only, so it is unit-tested; the
/// iPhone layer turns the results into `DayTimeline` inputs.
enum PFDayMerge {

    struct WeighIn: Equatable {
        var ts: Int?
        var kg: Double
    }

    struct Note: Equatable {
        var id: String
        var ts: Int?
        var title: String
        var subtitle: String
    }

    /// The planned sessions of one day, keyed by session id (the first event wins for a repeated id).
    static func planned(_ events: [PFDayEvent], day: String) -> [String: PFDayEvent] {
        var out: [String: PFDayEvent] = [:]
        for event in events where event.kind == "planned" && event.date == day {
            guard let id = event.sessionId, out[id] == nil else { continue }
            out[id] = event
        }
        return out
    }

    /// The day's weigh-ins as the server lists them.
    static func weighIns(_ events: [PFDayEvent], day: String) -> [WeighIn] {
        events.compactMap { event in
            guard event.kind == "weighIn", event.date == day, let kg = event.weightKg else { return nil }
            return WeighIn(ts: event.startTs, kg: kg)
        }
    }

    /// `existing` are the readings already on the phone, some with no clock time. A day-event weigh-in of
    /// the same weight (within 0.05 kg) gives that reading its time; one that matches nothing is added.
    static func mergeWeighIns(existing: [WeighIn], events: [WeighIn]) -> [WeighIn] {
        var out = existing
        for event in events {
            if let index = out.firstIndex(where: { abs($0.kg - event.kg) < 0.05 }) {
                if out[index].ts == nil { out[index].ts = event.ts }
            } else {
                out.append(event)
            }
        }
        return out
    }

    /// Niggles and other notes of one day, as My Day notes.
    static func notes(_ events: [PFDayEvent], day: String) -> [Note] {
        var out: [Note] = []
        for (index, event) in events.enumerated() where event.kind == "note" && event.date == day {
            if event.niggleSite != nil || event.niggleId != nil {
                let place = [event.niggleSide, event.niggleSite].compactMap { $0 }.joined(separator: " ")
                var bits = [place.isEmpty ? "Niggle" : place.prefix(1).uppercased() + place.dropFirst()]
                if let severity = event.niggleSeverity { bits.append("severity \(Safe.int(severity))") }
                if !event.niggleMovements.isEmpty { bits.append(event.niggleMovements.joined(separator: ", ")) }
                if event.niggleResolved { bits.append("resolved") }
                out.append(Note(id: "niggle-" + (event.niggleId ?? event.id ?? "\(index)"), ts: event.startTs,
                                title: "Niggle", subtitle: bits.joined(separator: " \u{00B7} ")))
            } else if let title = event.title {
                out.append(Note(id: "note-" + (event.id ?? "\(index)"), ts: event.startTs, title: title, subtitle: ""))
            }
        }
        return out
    }
}
