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

    var id: String { source + "|" + label }
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
