import Foundation
import StrandAnalytics

// Awards and challenges: counting only. An award's level is the highest step reached; there are no points. Pure, and also
// compiled into the UI test bundle for AwardsLogicTests.

enum AwardKind: String, CaseIterable, Codable, Identifiable {
    case chargeStreak, greenDays, sevenHourNights, hardDays, activities

    var id: String { rawValue }

    var steps: [Int] {
        switch self {
        case .chargeStreak: return [3, 7, 14, 30, 60, 100, 180, 365]
        case .greenDays: return [1, 10, 25, 50, 100]
        case .sevenHourNights: return [5, 25, 50, 100]
        case .hardDays: return [1, 10, 25, 50, 100]
        case .activities: return [1, 10, 25, 50, 100]
        }
    }

    var title: String {
        switch self {
        case .chargeStreak: return "Charge streak"
        case .greenDays: return "Green days"
        case .sevenHourNights: return "7 h nights"
        case .hardDays: return "Hard days"
        case .activities: return "Activities"
        }
    }

    var definition: String {
        switch self {
        case .chargeStreak: return "Days in a row with a WHOOP Charge. The award counts your longest run."
        case .greenDays: return "A green day: WHOOP Charge 67 or higher."
        case .sevenHourNights: return "A night with 7 h or more of WHOOP sleep."
        case .hardDays: return "A hard day: WHOOP strain 14.7 or more on the 0 to 21 scale."
        case .activities: return "Every activity on your Workouts list, from all sources, with duplicates removed."
        }
    }

    /// "25 green days", "7 day Charge streak".
    func phrase(_ count: Int) -> String {
        let one = count == 1
        switch self {
        case .chargeStreak: return "\(count) day Charge streak"
        case .greenDays: return "\(count) green day\(one ? "" : "s")"
        case .sevenHourNights: return "\(count) night\(one ? "" : "s") of 7 h"
        case .hardDays: return "\(count) hard day\(one ? "" : "s")"
        case .activities: return "\(count) activit\(one ? "y" : "ies")"
        }
    }

    var isWhoopOnly: Bool { self != .activities }

    /// What a challenge can be about.
    static let challengeKinds: [AwardKind] = [.greenDays, .sevenHourNights, .activities]
}

/// One WHOOP strap day. `strain21` is the day's strain on the 0 to 21 scale.
struct AwardDay: Equatable {
    var day: String
    var charge: Double?
    var asleepMin: Double?
    var strain21: Double?

    /// Banded on the rounded score, like the Charge ring.
    var isGreen: Bool { charge.map { $0.rounded() >= 67 } ?? false }
    var isSevenHourNight: Bool { asleepMin.map { $0 >= 420 } ?? false }
    /// On the one decimal the app prints, so a day shown as 14.7 counts.
    var isHard: Bool { strain21.map { ($0 * 10).rounded() >= 147 } ?? false }
}

struct AwardCounts: Equatable {
    /// What each award counts. An award that cannot be counted is absent.
    var totals: [AwardKind: Int]
    /// The Charge streak alive today (today not yet scored does not end it).
    var currentStreak: Int
}

struct AwardCelebration: Equatable, Identifiable {
    var kind: AwardKind
    var step: Int
    var id: String { "\(kind.rawValue)-\(step)" }
}

enum Awards {
    static func level(_ count: Int, _ kind: AwardKind) -> Int? { kind.steps.last { $0 <= count } }

    static func next(_ count: Int, _ kind: AwardKind) -> Int? { kind.steps.first { $0 > count } }

    /// `activities` is nil when the activity list could not be read.
    static func counts(days: [AwardDay], activities: Int?, today: String) -> AwardCounts {
        let streak = StreakCalculator.streaks(dayKeys: days.map(\.day), qualified: days.map { $0.charge != nil }, today: today)
        var totals: [AwardKind: Int] = [
            .chargeStreak: streak.longest,
            .greenDays: days.filter(\.isGreen).count,
            .sevenHourNights: days.filter(\.isSevenHourNight).count,
            .hardDays: days.filter(\.isHard).count,
        ]
        if let activities { totals[.activities] = activities }
        return AwardCounts(totals: totals, currentStreak: streak.current)
    }

    /// The steps newly reached since `seen` (award id to the highest step already accounted for, 0 for none). An award with no entry
    /// in `seen` is the first look at it: its steps are earned without a celebration. Several steps at once celebrate the highest.
    /// `seen` never goes down, so a step is celebrated once.
    static func newlyReached(_ totals: [AwardKind: Int], seen: [String: Int]) -> (celebrate: [AwardCelebration], seen: [String: Int]) {
        var out = seen
        var celebrate: [AwardCelebration] = []
        for kind in AwardKind.allCases {
            guard let count = totals[kind] else { continue }
            let reached = level(count, kind) ?? 0
            guard let before = seen[kind.rawValue] else {
                out[kind.rawValue] = reached
                continue
            }
            if reached > before {
                celebrate.append(AwardCelebration(kind: kind, step: reached))
                out[kind.rawValue] = reached
            }
        }
        return (celebrate, out)
    }
}

// MARK: - Challenges

/// A challenge the user set: what, how many, and by which day. The app creates none.
struct AwardChallenge: Codable, Equatable, Identifiable {
    var id: String
    var kind: AwardKind
    var target: Int
    var startDay: String
    var endDay: String

    enum State: Equatable { case running, finished, ended }

    /// Counted from the day it was started up to and including the end day. `activityDays` has one entry per activity.
    func progress(days: [AwardDay], activityDays: [String]) -> Int {
        func inside(_ day: String) -> Bool { day >= startDay && day <= endDay }
        switch kind {
        case .greenDays: return days.filter { inside($0.day) && $0.isGreen }.count
        case .sevenHourNights: return days.filter { inside($0.day) && $0.isSevenHourNight }.count
        case .activities: return activityDays.filter(inside).count
        case .chargeStreak, .hardDays: return 0
        }
    }

    func state(progress: Int, today: String) -> State {
        if progress >= target { return .finished }
        return today > endDay ? .ended : .running
    }
}
