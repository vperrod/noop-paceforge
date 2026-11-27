import Foundation
import StrandDesign

// Which figures go on the Day and Workout share cards, apart from the drawing so they can be tested on their own
// (ShareCardDataTests compiles this file). A figure with no data is nil and the card leaves it off.
//
// The Day card is a WHOOP card. Today's merged day can hold a figure Garmin filled in, so every figure, on the shown
// day and in the days behind its average, is kept only when a WHOOP row of that same day carries the same value.
// Garmin and WHOOP are never averaged together.

/// One day's figures that can go on the Day card. Effort is on the stored 0-100 scale.
struct ShareDayValues: Equatable {
    var day: String
    var charge: Double?
    var sleepMin: Double?
    var effort: Double?
    var hrv: Double?
    var restingHr: Double?

    /// Only the figures that one of `whoopRows` (this day's WHOOP rows, from before the merge) carries unchanged.
    func keepingWhoop(_ whoopRows: [ShareDayValues]) -> ShareDayValues {
        func kept(_ field: KeyPath<ShareDayValues, Double?>) -> Double? {
            guard let value = self[keyPath: field], whoopRows.contains(where: { $0[keyPath: field] == value }) else { return nil }
            return value
        }
        return ShareDayValues(day: day, charge: kept(\.charge), sleepMin: kept(\.sleepMin), effort: kept(\.effort),
                              hrv: kept(\.hrv), restingHr: kept(\.restingHr))
    }
}

struct ShareFigure: Equatable {
    var value: Double
    /// The app's 30-day mean of the days before the shown one (`LookBaseline.mean`), nil when it has none.
    var average: Double?
}

struct ShareDayFigures: Equatable {
    var charge: ShareFigure?
    var sleepMin: ShareFigure?
    var effort: ShareFigure?
    var hrv: ShareFigure?
    var restingHr: ShareFigure?

    var isEmpty: Bool { charge == nil && sleepMin == nil && effort == nil && hrv == nil && restingHr == nil }

    /// `shown` is the day on screen and `history` the merged days; `whoopRows` are the WHOOP rows behind them.
    /// `strapLiveEffort` is today's Effort scored live from the strap's heart rate, which no stored row carries yet.
    /// `hidesScores` is Settings > Hide numbers: Charge and Effort stay off the card.
    static func make(shown: ShareDayValues, history: [ShareDayValues], whoopRows: [ShareDayValues],
                     strapLiveEffort: Double?, hidesScores: Bool, calendar: Calendar) -> ShareDayFigures {
        let whoopByDay = Dictionary(grouping: whoopRows, by: \.day)
        let earlier = history.filter { $0.day < shown.day }.map { $0.keepingWhoop(whoopByDay[$0.day] ?? []) }
        var own = shown.keepingWhoop(whoopByDay[shown.day] ?? [])
        if let strapLiveEffort, shown.effort == strapLiveEffort { own.effort = strapLiveEffort }
        let date = LookDayKey.date(shown.day, calendar: calendar)

        func figure(_ field: KeyPath<ShareDayValues, Double?>, zeroIsData: Bool = false) -> ShareFigure? {
            guard let value = own[keyPath: field], value.isFinite, zeroIsData || value > 0 else { return nil }
            let rows = earlier.compactMap { day -> (day: String, value: Double)? in
                guard let v = day[keyPath: field], zeroIsData || v > 0 else { return nil }
                return (day: day.day, value: v)
            }
            let average = date.flatMap {
                LookBaseline.mean(of: LookSeries.points(rows, calendar: calendar), before: $0, calendar: calendar)
            }
            return ShareFigure(value: value, average: average)
        }

        return ShareDayFigures(charge: hidesScores ? nil : figure(\.charge, zeroIsData: true),
                               sleepMin: figure(\.sleepMin),
                               effort: hidesScores ? nil : figure(\.effort, zeroIsData: true),
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
