import Foundation

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
