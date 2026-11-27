import Foundation
import WhoopStore

/// Garmin's Charge, carried in reports beside the WHOOP strap's as a reference. It never enters a WHOOP figure, an average
/// of one, a target, a state or an alert.
enum GarminChargeReference {
    /// The mean of the days from `from` through `to` ("yyyy-MM-dd") that have a Garmin Charge; nil when none has.
    static func mean(_ byDay: [String: Double], from: String, to: String) -> Double? {
        let values = byDay.filter { $0.key >= from && $0.key <= to }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// "Garmin Charge 61 (reference only)" for a day or a period; nil when it has no Garmin Charge.
    static func line(_ byDay: [String: Double], from: String, to: String) -> String? {
        mean(byDay, from: from, to: to).map { "Garmin Charge \(Int($0.rounded())) (reference only)" }
    }
}

/// Garmin's steps and active energy for the coach, as lines of their own beside the strap's. A reference only: never added
/// to or averaged with the strap's figures, and a figure Garmin did not report has no line.
enum GarminActivityReference {
    /// The mean of each figure over the days from `from` through `to` that have it. `unit` is "" for a day, "/day" for a period.
    static func lines(_ rows: [DailyMetric], from: String, to: String, unit: String = "") -> [String] {
        let inRange = rows.filter { $0.day >= from && $0.day <= to }
        func mean(_ values: [Double]) -> Int? {
            values.isEmpty ? nil : Int((values.reduce(0, +) / Double(values.count)).rounded())
        }
        return [
            mean(inRange.compactMap { $0.steps.map(Double.init) }).map { "Garmin (reference only): steps \($0)\(unit)" },
            mean(inRange.compactMap(\.activeKcalEst)).map { "Garmin (reference only): active energy \($0) kcal\(unit)" },
        ].compactMap { $0 }
    }
}
