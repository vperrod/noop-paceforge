import XCTest

/// Unit checks for award counting, celebrations and challenges (AwardsLogic.swift, compiled into this bundle). Made-up days.
final class AwardsLogicTests: XCTestCase {
    private func day(_ number: Int, charge: Double? = nil, asleep: Double? = nil, strain: Double? = nil) -> AwardDay {
        AwardDay(day: String(format: "2030-03-%02d", number), charge: charge, asleepMin: asleep, strain21: strain)
    }

    private var days: [AwardDay] {
        [day(1, charge: 66.4, asleep: 419, strain: 14.64), day(2, charge: 66.5, asleep: 420, strain: 14.66),
         day(3, charge: 80, asleep: 500, strain: 18), day(5, charge: 50), day(6, asleep: 430)]
    }

    private var counts: AwardCounts { Awards.counts(days: days, activities: 12, today: "2030-03-06") }

    func testTheStreakAwardCountsTheLongestRunOfDaysWithACharge() {
        XCTAssertEqual(counts.totals[.chargeStreak], 3)
    }

    func testTheCurrentStreakAllowsTodayToBeUnscored() {
        XCTAssertEqual(counts.currentStreak, 1)
    }

    func testAGreenDayIsBandedOnTheRoundedCharge() {
        XCTAssertEqual(counts.totals[.greenDays], 2)
    }

    func testASevenHourNightStartsAtFourHundredAndTwentyMinutes() {
        XCTAssertEqual(counts.totals[.sevenHourNights], 3)
    }

    func testAHardDayStartsAtTheStrainPrintedAsFourteenPointSeven() {
        XCTAssertEqual(counts.totals[.hardDays], 2)
    }

    func testAnActivityListThatCannotBeReadIsNotCounted() {
        XCTAssertNil(Awards.counts(days: days, activities: nil, today: "2030-03-06").totals[.activities])
    }

    func testTheLevelIsTheHighestStepReached() {
        XCTAssertEqual(Awards.level(49, .greenDays), 25)
    }

    func testTheNextStepIsTheFirstAboveTheCount() {
        XCTAssertEqual(Awards.next(50, .chargeStreak), 60)
    }

    func testPastTheLastStepThereIsNoNextOne() {
        XCTAssertNil(Awards.next(365, .chargeStreak))
    }

    func testStepsAlreadyReachedAtFirstRunAreNotCelebrated() {
        XCTAssertEqual(Awards.newlyReached([.greenDays: 30, .activities: 4], seen: [:]).celebrate, [])
    }

    func testTheFirstRunRemembersTheStepsAlreadyReached() {
        XCTAssertEqual(Awards.newlyReached([.greenDays: 30, .hardDays: 0], seen: [:]).seen, ["greenDays": 25, "hardDays": 0])
    }

    func testAStepReachedLaterIsCelebratedWithTheHighestOne() {
        XCTAssertEqual(Awards.newlyReached([.greenDays: 55], seen: ["greenDays": 10]).celebrate,
                       [AwardCelebration(kind: .greenDays, step: 50)])
    }

    func testAStepIsCelebratedOnlyOnce() {
        let first = Awards.newlyReached([.greenDays: 25], seen: ["greenDays": 10])
        XCTAssertEqual(Awards.newlyReached([.greenDays: 26], seen: first.seen).celebrate, [])
    }

    func testACountThatDropsAndReturnsIsNotCelebratedAgain() {
        let dropped = Awards.newlyReached([.greenDays: 20], seen: ["greenDays": 25])
        XCTAssertEqual(Awards.newlyReached([.greenDays: 25], seen: dropped.seen).celebrate, [])
    }

    private func challenge(_ kind: AwardKind, target: Int) -> AwardChallenge {
        AwardChallenge(id: "c", kind: kind, target: target, startDay: "2030-03-02", endDay: "2030-03-05")
    }

    func testAChallengeCountsFromItsStartDayToItsEndDay() {
        XCTAssertEqual(challenge(.sevenHourNights, target: 5).progress(days: days, activityDays: []), 2)
    }

    func testAnActivityChallengeCountsEveryActivityInside() {
        XCTAssertEqual(challenge(.activities, target: 5)
            .progress(days: days, activityDays: ["2030-03-01", "2030-03-02", "2030-03-02", "2030-03-05", "2030-03-06"]), 3)
    }

    func testAChallengeThatReachedItsTargetIsFinishedEvenAfterItsEnd() {
        XCTAssertEqual(challenge(.greenDays, target: 2).state(progress: 2, today: "2030-03-20"), .finished)
    }

    func testAChallengeShortOfItsTargetRunsOnItsLastDay() {
        XCTAssertEqual(challenge(.greenDays, target: 2).state(progress: 1, today: "2030-03-05"), .running)
    }

    func testAChallengeShortOfItsTargetHasEndedAfterItsLastDay() {
        XCTAssertEqual(challenge(.greenDays, target: 2).state(progress: 1, today: "2030-03-06"), .ended)
    }
}
