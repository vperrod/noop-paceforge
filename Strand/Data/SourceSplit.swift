import Foundation
import StrandDesign
import WhoopStore

/// One daily figure from one device.
struct SourceReading: Equatable {
    /// "WHOOP" or "Garmin".
    let source: String
    let value: Double
}

/// A daily figure split by the device that measured it: the WHOOP strap's (`Repository.strapDays`) and Garmin's
/// (`Repository.garminDays`). Screens that show both show them apart: never joined into one line, never averaged.
enum SourceSplit {
    static let whoop = "WHOOP"
    static let garmin = "Garmin"

    /// `day`'s readings, WHOOP first; a device without a value for the day has no entry.
    static func readings(day: String, whoop whoopDays: [DailyMetric], garmin garminDays: [DailyMetric],
                         _ value: (DailyMetric) -> Double?) -> [SourceReading] {
        [(whoop, whoopDays), (garmin, garminDays)].compactMap { source, days in
            days.last(where: { $0.day == day }).flatMap(value).map { SourceReading(source: source, value: $0) }
        }
    }

    /// "WHOOP 52 ms · Garmin 40 ms": each device's own mean of its points; nil when neither has any.
    static func averages(whoop whoopPoints: [TrendPoint], garmin garminPoints: [TrendPoint],
                         format: (Double) -> String) -> String? {
        let parts = [(whoop, whoopPoints), (garmin, garminPoints)].compactMap { source, points -> String? in
            points.isEmpty ? nil : "\(source) \(format(points.map(\.value).reduce(0, +) / Double(points.count)))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// Daily points with a new line segment after every missing day, so a day without a reading stays a gap.
    static func gapped(_ points: [TrendPoint]) -> [TrendPoint] {
        let segments = hrGapSegments(bucketTs: points.map { Int($0.date.timeIntervalSince1970) }, bucketSeconds: 86_400)
        return zip(points, segments).map { TrendPoint(date: $0.date, value: $0.value, segment: $1) }
    }
}
