import Foundation
import StrandDesign
import WhoopStore

// The awards' readings and what is kept: the highest step already accounted for per award, and the challenges. The WHOOP awards
// read the strap's own days; Activities counts the Workouts list.

@MainActor
final class AwardsStore: ObservableObject {
    static let shared = AwardsStore()

    @Published private(set) var counts: AwardCounts?
    @Published private(set) var days: [AwardDay] = []
    /// The local day of every activity on the Workouts list.
    @Published private(set) var activityDays: [String] = []
    @Published private(set) var today = ""
    @Published private(set) var challenges: [AwardChallenge] = []
    /// Steps newly reached and not yet shown, oldest first.
    @Published private(set) var celebrations: [AwardCelebration] = []

    private static let seenKey = "noop.awards.seen"
    private static let challengesKey = "noop.awards.challenges"

    private init() {
        if !isFixture, let data = UserDefaults.standard.data(forKey: Self.challengesKey),
           let stored = try? JSONDecoder().decode([AwardChallenge].self, from: data) {
            challenges = stored
        }
    }

    func refresh(repo: Repository, now: Date = Date()) async {
        #if DEBUG
        if let fixture = AwardsFixture.reading {
            guard counts == nil else { return }
            apply(days: fixture.days, activityDays: fixture.activityDays, today: fixture.today, seen: fixture.seen)
            return
        }
        #endif
        let strap = repo.strapDays.map { row in
            AwardDay(day: row.day, charge: row.recovery, asleepMin: row.totalSleepMin,
                     strain21: row.strain.map { UnitFormatter.effortValue($0, scale: .whoop) })
        }
        let workouts = await repo.workoutRows(days: 4000, reconcilesHr: false)
        let activity = workouts.map { Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))) }
        guard !Task.isCancelled else { return }
        let stored = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int] ?? [:]
        // With no strap day loaded there is nothing to remember yet: the first real look must not read as "newly reached".
        apply(days: strap, activityDays: activity, today: Repository.logicalDayKey(now), seen: strap.isEmpty ? nil : stored)
    }

    private func apply(days: [AwardDay], activityDays: [String], today: String, seen: [String: Int]?) {
        let counts = Awards.counts(days: days, activities: activityDays.count, today: today)
        if self.days != days { self.days = days }
        if self.activityDays != activityDays { self.activityDays = activityDays }
        if self.today != today { self.today = today }
        if self.counts != counts { self.counts = counts }
        guard let seen else { return }
        let result = Awards.newlyReached(counts.totals, seen: seen)
        if !isFixture { UserDefaults.standard.set(result.seen, forKey: Self.seenKey) }
        if presentsCelebrations, !result.celebrate.isEmpty { celebrations += result.celebrate }
    }

    func dismissCelebration() {
        if !celebrations.isEmpty { celebrations.removeFirst() }
    }

    // MARK: Challenges

    func start(kind: AwardKind, target: Int, endDay: String) {
        challenges.append(AwardChallenge(id: UUID().uuidString, kind: kind, target: target, startDay: today, endDay: endDay))
        saveChallenges()
    }

    func remove(_ challenge: AwardChallenge) {
        challenges.removeAll { $0.id == challenge.id }
        saveChallenges()
    }

    private func saveChallenges() {
        guard !isFixture, let data = try? JSONEncoder().encode(challenges) else { return }
        UserDefaults.standard.set(data, forKey: Self.challengesKey)
    }

    // MARK: UI tests

    private var isFixture: Bool {
        #if DEBUG
        return AwardsFixture.reading != nil
        #else
        return false
        #endif
    }

    private var presentsCelebrations: Bool {
        #if DEBUG
        // Other UI tests seed history while they run; only an awards fixture may put a celebration over their screens.
        if CommandLine.arguments.contains("--demo-seed") { return isFixture }
        #endif
        return true
    }
}

#if DEBUG
/// Made-up history for simulator screenshots and UI tests: `-AwardsFixture normal | celebrate`. Nothing here is real data.
enum AwardsFixture {
    struct Reading {
        var days: [AwardDay]
        var activityDays: [String]
        var today: String
        var seen: [String: Int]
    }

    static let reading: Reading? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-AwardsFixture"), args.index(after: i) < args.endIndex else { return nil }
        let celebrates = args[args.index(after: i)] == "celebrate"
        let today = "2030-03-13"
        let green = celebrates ? 25 : 21
        let days = (0..<42).map { back in
            AwardDay(day: DailyTiming.addDays(today, back - 41), charge: back < green ? 78 : 52,
                     asleepMin: back % 2 == 0 ? 440 : 395, strain21: back % 14 == 0 ? 15.2 : 11.0)
        }
        let activity = (0..<37).map { DailyTiming.addDays(today, -$0) }
        var seen = ["chargeStreak": 30, "greenDays": 10, "sevenHourNights": 5, "hardDays": 1, "activities": 25]
        if !celebrates { seen = [:] }
        return Reading(days: days, activityDays: activity, today: today, seen: seen)
    }()
}
#endif
