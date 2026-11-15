import Foundation

// The rows a PaceForge ring's page lists under "What explains it": only values the phone already holds (the saved readiness
// document), each naming its source. Garmin's numbers and PaceForge's own calculation are never merged. Foundation-only so the
// unit tests compile it (see project.yml, StrandTests).

struct PFContributorRow: Equatable, Identifiable {
    let label: String
    /// Nil for a driver sentence the server sends as text only.
    let value: String?
    let note: String?
    /// "Garmin" or "PaceForge", as PFSourceTag draws it.
    let source: String
    /// The row's share of the whole, 0 to 1, drawn as a bar when set (the Strain parts).
    var share: Double? = nil

    var id: String { source + "|" + label }
}

/// One session's part of the day's Strain, from `daily.strain.strain_parts` in `data/fitness.json` (biggest first).
struct PFStrainPart: Equatable {
    var label: String
    var value: Double
    var unit: String
    /// This session's share of the day's load, 0 to 1.
    var share: Double?
}

/// The readiness document's fields the ring pages read, by name (DayReadings is iOS-only and not in the test bundle).
struct PFRingFacts: Equatable {
    struct Factor: Equatable {
        var name: String
        var value: String?
        var status: String?
    }

    var garminReadiness: Double?
    var garminLevel: String?
    var garminFactors: [Factor] = []
    var garminRecoveryTimeH: Double?
    var paceforgeDrivers: [String] = []
    var garminSleepFactor: Double?
    var garminSleepFactorStatus: String?
    var lastNightNeedText: String?
    var tonightNeedText: String?
    var tonightBedtime: String?
}

enum PFRingRows {
    /// Where the Strain parts say they come from: PaceForge's calculation on Garmin's recordings.
    static let strainSource = "PaceForge, from Garmin data"

    /// `daily.strain.strain_parts`; empty when the server sends none (a rest day, an older server). A part without a label or a finite
    /// value is skipped, a share outside 0 to 1 is dropped.
    static func strainParts(_ strain: PFJ) -> [PFStrainPart] {
        strain["strain_parts"].array.compactMap { part in
            guard let label = part["label"].text, let value = part["value"].double, value.isFinite else { return nil }
            let share = part["share"].double.flatMap { $0.isFinite && $0 >= 0 && $0 <= 1 ? $0 : nil }
            return PFStrainPart(label: label, value: value, unit: part["unit"].text ?? "load", share: share)
        }
    }

    /// One row per session: its load and its share of the day.
    static func strain(_ parts: [PFStrainPart]) -> [PFContributorRow] {
        parts.map { part in
            PFContributorRow(label: part.label, value: PFFormat.trimmed(part.value.rounded()) + " " + part.unit,
                             note: part.share.map { "\(Safe.int($0 * 100)) % of the day" }, source: strainSource, share: part.share)
        }
    }

    static func recovery(_ f: PFRingFacts) -> [PFContributorRow] {
        var out: [PFContributorRow] = []
        if let score = f.garminReadiness {
            out.append(PFContributorRow(label: "Garmin training readiness", value: PFFormat.trimmed(score), note: f.garminLevel, source: "Garmin"))
        }
        for factor in f.garminFactors {
            out.append(PFContributorRow(label: PFFormat.capitalized(factor.name), value: factor.value, note: factor.status, source: "Garmin"))
        }
        if let hours = f.garminRecoveryTimeH, hours >= 0 {
            out.append(PFContributorRow(label: "Recovery time", value: PFFormat.trimmed(hours) + " h", note: nil, source: "Garmin"))
        }
        for driver in f.paceforgeDrivers {
            out.append(PFContributorRow(label: driver, value: nil, note: nil, source: "PaceForge"))
        }
        return out
    }

    static func sleep(_ f: PFRingFacts) -> [PFContributorRow] {
        var out: [PFContributorRow] = []
        if let factor = f.garminSleepFactor {
            out.append(PFContributorRow(label: "Sleep factor in Garmin readiness", value: PFFormat.trimmed(factor),
                                        note: f.garminSleepFactorStatus, source: "Garmin"))
        }
        if let text = f.lastNightNeedText {
            out.append(PFContributorRow(label: "Last night's sleep need", value: text, note: nil, source: "PaceForge"))
        }
        if let text = f.tonightNeedText {
            out.append(PFContributorRow(label: "Tonight's sleep need", value: text, note: nil, source: "PaceForge"))
        }
        if let bedtime = f.tonightBedtime {
            out.append(PFContributorRow(label: "Bedtime tonight", value: bedtime, note: nil, source: "PaceForge"))
        }
        return out
    }
}
