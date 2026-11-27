import Foundation
import ImageIO
import StrandDesign

// Which figures go on the Day and Workout share cards, and how large a picked photo is decoded, apart from the
// drawing so they can be tested on their own (ShareCardDataTests compiles this file). A figure with no data is nil
// and the card leaves it off.
//
// The Day card carries the strap days only (never Garmin). Each figure is traced to the device that measured it on its own
// day, a figure no device can be named for is left off, and an average holds only the days that same device measured.

/// One day's figures that can go on the Day card. Effort is on the stored 0-100 scale.
struct ShareDayValues: Equatable {
    var day: String
    var charge: Double?
    var sleepMin: Double?
    var effort: Double?
    var hrv: Double?
    var restingHr: Double?
}

/// One stored row of a day, from before any merge, with the name of the device that measured it.
struct ShareStrapRow: Equatable {
    var values: ShareDayValues
    var provider: String
}

struct ShareFigure: Equatable {
    var value: Double
    /// The app's 30-day mean of the days before the shown one (`LookBaseline.mean`) that the same device measured,
    /// nil when it has none.
    var average: Double?
    var provider: String
}

struct ShareDayFigures: Equatable {
    var charge: ShareFigure?
    var sleepMin: ShareFigure?
    var effort: ShareFigure?
    var hrv: ShareFigure?
    var restingHr: ShareFigure?

    /// "WHOOP data", naming every device that measured a figure on the card. nil on a card with no figure.
    var sourceLine: String? {
        var names: [String] = []
        for figure in [charge, sleepMin, effort, hrv, restingHr].compactMap({ $0 }) where !names.contains(figure.provider) {
            names.append(figure.provider)
        }
        return names.isEmpty ? nil : "\(names.joined(separator: " + ")) data"
    }

    /// `shown` is the strap day on screen and `history` the strap days; `rows` are the stored rows behind them, in the
    /// order the merge prefers them. `strapLiveEffort` is today's Effort scored live from the heart rate of the device
    /// `liveProvider`, which no stored row carries yet. `hidesScores` is Settings > Hide numbers: Charge and Effort stay off.
    static func make(shown: ShareDayValues, history: [ShareDayValues], rows: [ShareStrapRow],
                     strapLiveEffort: Double?, liveProvider: String, hidesScores: Bool,
                     calendar: Calendar) -> ShareDayFigures {
        let rowsByDay = Dictionary(grouping: rows, by: \.values.day)
        let date = LookDayKey.date(shown.day, calendar: calendar)

        func provider(_ day: String, _ field: KeyPath<ShareDayValues, Double?>, _ value: Double) -> String? {
            rowsByDay[day]?.first { $0.values[keyPath: field] == value }?.provider
        }

        func figure(_ field: KeyPath<ShareDayValues, Double?>, zeroIsData: Bool = false,
                    live: Double? = nil) -> ShareFigure? {
            guard let value = shown[keyPath: field], value.isFinite, zeroIsData || value > 0,
                  let measuredBy = value == live ? liveProvider : provider(shown.day, field, value) else { return nil }
            let earlier = history.compactMap { day -> (day: String, value: Double)? in
                guard day.day < shown.day, let v = day[keyPath: field], zeroIsData || v > 0,
                      provider(day.day, field, v) == measuredBy else { return nil }
                return (day: day.day, value: v)
            }
            let average = date.flatMap {
                LookBaseline.mean(of: LookSeries.points(earlier, calendar: calendar), before: $0, calendar: calendar)
            }
            return ShareFigure(value: value, average: average, provider: measuredBy)
        }

        return ShareDayFigures(charge: hidesScores ? nil : figure(\.charge, zeroIsData: true),
                               sleepMin: figure(\.sleepMin),
                               effort: hidesScores ? nil : figure(\.effort, zeroIsData: true, live: strapLiveEffort),
                               hrv: figure(\.hrv),
                               restingHr: figure(\.restingHr))
    }
}

/// What a recorded workout has for its card. A stored zero is no reading, except for Effort, where it is a score.
struct ShareWorkoutFigures: Equatable {
    var durationS: Double?
    var avgHr: Int?
    var maxHr: Int?
    var kcal: Double?
    var distanceM: Double?
    var effort: Double?

    init(durationS: Double?, avgHr: Int?, maxHr: Int?, kcal: Double?, distanceM: Double?, effort: Double?) {
        self.durationS = durationS.flatMap { $0 > 0 ? $0 : nil }
        self.avgHr = avgHr.flatMap { $0 > 0 ? $0 : nil }
        self.maxHr = maxHr.flatMap { $0 > 0 ? $0 : nil }
        self.kcal = kcal.flatMap { $0 > 0 ? $0 : nil }
        self.distanceM = distanceM.flatMap { $0 > 0 ? $0 : nil }
        self.effort = effort
    }
}

/// A picked photo, decoded only as large as the card's image needs.
enum SharePhoto {
    /// The longest side to decode at, so the upright picture still covers `target` in aspect-fill. Never above its own.
    static func maxPixelSide(upright: CGSize, covering target: CGSize) -> Int {
        let longest = max(upright.width, upright.height)
        let needed = max(target.width * longest / upright.width, target.height * longest / upright.height)
        return Int(min(longest, needed).rounded(.up))
    }

    /// The upright, downscaled picture (an ImageIO thumbnail: the full-size picture is never held).
    /// nil when `data` is not a picture that can be read.
    static func downscaled(_ data: Data, covering target: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
        // EXIF orientations 5 to 8 turn the picture by a quarter.
        let isTurned = (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
        let upright = CGSize(width: isTurned ? height : width, height: isTurned ? width : height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSide(upright: upright, covering: target),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
