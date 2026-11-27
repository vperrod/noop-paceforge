import Foundation

// The daily timing plan's arithmetic. Pure: times are minutes after midnight and days are "yyyy-MM-dd"; nothing here reads a
// clock or a store. Also compiled into the UI test bundle, so DailyTimingLogicTests can call it.

enum DailyTiming {
    /// A night under this much WHOOP time asleep (6 h 30) brings the nap advice.
    static let shortNightMin = 390.0
    static let hardTrainingLeadMin = 4 * 60
    static let dimLightsLeadMin = 3 * 60
    /// An early start moves the wake time this much a day; the last step is the remainder.
    static let wakeStepMin = 60
    static let napStartMin = 13 * 60
    static let napEndMin = 16 * 60
    /// The sleep planner's own floor for a main sleep: anything shorter is a nap.
    static let mainSleepFloorSec = 3 * 3_600
    static let patternNights = 14

    static func wrap(_ minutes: Int) -> Int { ((minutes % 1440) + 1440) % 1440 }

    static func clock(_ minutes: Int) -> String {
        let m = wrap(minutes)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// "6 h 59", "45 min", "8 h".
    static func duration(_ minutes: Int) -> String {
        let m = abs(minutes)
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)"
    }

    /// Minutes from a time of day forward round the clock to bedtime.
    static func minutesBeforeBed(_ minutes: Int, bed: Int) -> Int { wrap(bed - minutes) }

    static func needsNap(asleepMin: Double?) -> Bool {
        guard let asleepMin else { return false }
        return asleepMin < shortNightMin
    }

    // MARK: - Cues

    enum Kind: String, CaseIterable {
        case daylight, nap, coffee, session, hardTraining, dimLights, bed
    }

    struct Cue: Equatable {
        var kind: Kind
        /// nil for a cue with no clock time (daylight).
        var minutes: Int?
    }

    /// The day's cues: daylight first (no time), then the timed ones in the order they come on the way to bed.
    static func cues(bed: Int, coffeeCutoff: Int, asleepMin: Double?, sessionStart: Int?) -> [Cue] {
        var timed = [
            Cue(kind: .coffee, minutes: wrap(coffeeCutoff)),
            Cue(kind: .hardTraining, minutes: wrap(bed - hardTrainingLeadMin)),
            Cue(kind: .dimLights, minutes: wrap(bed - dimLightsLeadMin)),
        ]
        if needsNap(asleepMin: asleepMin) { timed.append(Cue(kind: .nap, minutes: napStartMin)) }
        if let sessionStart { timed.append(Cue(kind: .session, minutes: wrap(sessionStart))) }
        timed.sort { minutesBeforeBed($0.minutes ?? bed, bed: bed) > minutesBeforeBed($1.minutes ?? bed, bed: bed) }
        return [Cue(kind: .daylight, minutes: nil)] + timed + [Cue(kind: .bed, minutes: wrap(bed))]
    }

    /// The first timed cue still ahead of `now`, bed left out (the Today card states bedtime on its own line).
    static func nextCue(_ cues: [Cue], bed: Int, bedDate: Date, now: Date) -> Cue? {
        cues.first { cue in
            guard cue.kind != .bed, let minutes = cue.minutes else { return false }
            return bedDate.addingTimeInterval(-Double(minutesBeforeBed(minutes, bed: bed)) * 60) > now
        }
    }

    /// Minutes from the end of a session to bedtime; negative when it ends after bedtime.
    static func gapToBed(start: Int, durationMin: Int, bed: Int) -> Int {
        minutesBeforeBed(start, bed: bed) - durationMin
    }

    static func endsInsideHardWindow(start: Int, durationMin: Int, bed: Int) -> Bool {
        gapToBed(start: start, durationMin: durationMin, bed: bed) < hardTrainingLeadMin
    }

    // MARK: - Days

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static func date(_ day: String) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func day(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func addDays(_ iso: String, _ count: Int) -> String {
        guard let start = date(iso), let moved = utc.date(byAdding: .day, value: count, to: start) else { return iso }
        return day(moved)
    }

    /// 1 = Sunday ... 7 = Saturday.
    static func weekday(_ iso: String) -> Int? { date(iso).map { utc.component(.weekday, from: $0) } }

    static func isWeekend(_ iso: String) -> Bool {
        let day = weekday(iso)
        return day == 1 || day == 7
    }

    // MARK: - Weekend pattern

    /// One sleep block as local wake day, wake minutes and length in seconds.
    struct Block: Equatable {
        var wakeDay: String
        var wakeMinutes: Int
        var lengthSec: Int
    }

    /// The main sleep of each wake day: its longest block, naps left out.
    static func mainNights(_ blocks: [Block]) -> [String: Block] {
        var out: [String: Block] = [:]
        for block in blocks where block.lengthSec >= mainSleepFloorSec {
            if let kept = out[block.wakeDay], kept.lengthSec >= block.lengthSec { continue }
            out[block.wakeDay] = block
        }
        return out
    }

    struct Pattern: Equatable {
        var weekdayWake: Int?
        var weekendWake: Int?
        var weekdayNights: Int
        var weekendNights: Int
    }

    /// Median wake time on weekdays and on weekend days over the 14 wake days ending today. A weekend night is one that ends on a
    /// Saturday or a Sunday.
    static func pattern(_ nights: [String: Block], today: String) -> Pattern {
        let first = addDays(today, -(patternNights - 1))
        let recent = nights.values.filter { $0.wakeDay >= first && $0.wakeDay <= today }
        let weekend = recent.filter { isWeekend($0.wakeDay) }.map(\.wakeMinutes)
        let weekdays = recent.filter { !isWeekend($0.wakeDay) }.map(\.wakeMinutes)
        return Pattern(weekdayWake: median(weekdays), weekendWake: median(weekend),
                       weekdayNights: weekdays.count, weekendNights: weekend.count)
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : Int((Double(sorted[mid - 1] + sorted[mid]) / 2).rounded())
    }

    // MARK: - Early start

    /// How far the wake time has to move earlier; nil when the new time is not earlier (up to half a day round the clock).
    static func earlierBy(current: Int, target: Int) -> Int? {
        let shift = wrap(current - target)
        return shift == 0 || shift > 720 ? nil : shift
    }

    /// The total shift reached on each shifting day: 60, 120, ... and the remainder last.
    static func cumulativeShifts(total: Int) -> [Int] {
        guard total > 0 else { return [] }
        return stride(from: wakeStepMin, to: total, by: wakeStepMin).map { $0 } + [total]
    }

    struct ShiftDay: Equatable {
        var day: String
        var wake: Int
        var bed: Int
    }

    struct EarlyPlan: Equatable {
        var days: [ShiftDay]
        /// False when the shifting days run past the day itself.
        var reachesTargetInTime: Bool
    }

    /// Bedtime moves with the wake time, so the time in bed stays the planner's.
    static func earlyPlan(currentWake: Int, bed: Int, targetWake: Int, startDay: String, eventDay: String) -> EarlyPlan? {
        guard let total = earlierBy(current: currentWake, target: targetWake) else { return nil }
        let all = cumulativeShifts(total: total).enumerated().map { index, shift in
            ShiftDay(day: addDays(startDay, index), wake: wrap(currentWake - shift), bed: wrap(bed - shift))
        }
        let inTime = all.filter { $0.day <= eventDay }
        return EarlyPlan(days: inTime, reachesTargetInTime: inTime.count == all.count)
    }
}
