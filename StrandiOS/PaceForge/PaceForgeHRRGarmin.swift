import Foundation

/// Garmin's own recovery heart rate (`hrr_garmin` in an activity's detail): the drop over the 2 minutes after the
/// last Stop, as the watch recorded it. Nothing here is estimated; a missing key reads as "not recorded".
struct PFHRRGarmin: Equatable {
    /// Beats the heart rate fell in 2 minutes (HR at the stop minus HR 2 minutes later).
    var dropBpm: Int
    /// Heart rate 2 minutes after the stop, and at the stop. Both only when the watch's file carried them.
    var hr2min: Int?
    var stopBpm: Int?

    static let tip = "To get Garmin's recovery HR: after the last Stop wait 2 minutes before Save."

    /// "Garmin recovery heart rate: -46 bpm in 2 minutes" (a rise shows "+").
    var headline: String {
        let signed = dropBpm > 0 ? "-\(dropBpm)" : dropBpm < 0 ? "+\(-dropBpm)" : "0"
        return "Garmin recovery heart rate: \(signed) bpm in 2 minutes"
    }

    /// "149 at the stop, 103 two minutes later", only when both readings are there.
    var detail: String? {
        guard let stopBpm, let hr2min else { return nil }
        return "\(stopBpm) at the stop, \(hr2min) two minutes later"
    }

    /// Nil unless the document carries a numeric `drop_bpm`.
    static func parse(_ j: PFJ) -> PFHRRGarmin? {
        guard let drop = j["drop_bpm"].int else { return nil }
        return PFHRRGarmin(dropBpm: drop, hr2min: j["hr_2min"].int, stopBpm: j["stop_bpm"].int)
    }

    /// NOOP's workout row has no column for it, so PaceForge's sync leaves Garmin's three values in the row's
    /// notes as ` · hrr_garmin={"drop_bpm":46,"hr_2min":103,"stop_bpm":149}`. Nil unless a numeric drop is there.
    static func fromNotes(_ notes: String?) -> PFHRRGarmin? {
        guard let notes, let marker = notes.range(of: "hrr_garmin="),
              let close = notes[marker.upperBound...].firstIndex(of: "}") else { return nil }
        let json = String(notes[marker.upperBound...close])
        return parse(PFJ(data: Data(json.utf8)))
    }
}
