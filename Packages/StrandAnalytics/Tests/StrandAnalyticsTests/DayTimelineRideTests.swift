import XCTest
@testable import StrandAnalytics

/// A bike ride PaceForge logged with a ride id (no Garmin activity) is one workout row in My Day that opens
/// the ride screen. All values are made up.
final class DayTimelineRideTests: XCTestCase {

    /// 2026-06-10 00:00 UTC.
    private let day0 = 1_781_049_600

    private func at(_ hour: Int, _ minute: Int = 0) -> Int { day0 + hour * 3600 + minute * 60 }
    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    private func input() -> DayTimeline.Input {
        DayTimeline.Input(dayStart: date(day0), dayEnd: date(day0 + 86_400), now: date(day0 + 2 * 86_400))
    }

    private func ride(_ id: String = "bike:2026-06-10", startTs: Int? = nil, endTs: Int? = nil,
                      durationSec: Int? = nil) -> DayTimeline.Input.Ride {
        .init(id: id, title: "Synthetic sweet spot", detail: "60 min \u{00B7} NP 188 W", startTs: startTs,
              endTs: endTs, durationSec: durationSec, avgHr: 148)
    }

    func testARideIsAWorkoutRowThatOpensItsRide() {
        var i = input()
        i.rides = [ride(startTs: at(7, 30), endTs: at(8, 30))]
        let event = DayTimeline.build(i).events.first { $0.id == "ride-bike:2026-06-10" }
        XCTAssertEqual(event?.route, .ride(id: "bike:2026-06-10"))
    }

    func testARideIsAWorkout() {
        var i = input()
        i.rides = [ride(startTs: at(7, 30))]
        XCTAssertEqual(DayTimeline.build(i).events.first?.kind, .workout)
    }

    func testARideWithAClockTimeIsATimedRow() {
        var i = input()
        i.rides = [ride(startTs: at(7, 30), endTs: at(8, 30))]
        XCTAssertEqual(DayTimeline.build(i).events.first?.isUntimed, false)
    }

    func testARideWithoutAClockTimeIsListedAllDay() {
        var i = input()
        i.rides = [ride()]
        XCTAssertEqual(DayTimeline.build(i).events.first?.isUntimed, true)
    }

    func testARideRunsForItsDurationWhenItHasNoEnd() {
        var i = input()
        i.rides = [ride(startTs: at(7, 30), durationSec: 3600)]
        XCTAssertEqual(DayTimeline.build(i).events.first?.end, date(at(8, 30)))
    }

    func testARideStartingOutsideTheDayIsUntimed() {
        var i = input()
        i.rides = [ride(startTs: day0 - 3600)]
        XCTAssertEqual(DayTimeline.build(i).events.first?.isUntimed, true)
    }

    func testARideCarriesThePaceForgeBadge() {
        var i = input()
        i.rides = [ride(startTs: at(7, 30))]
        XCTAssertEqual(DayTimeline.build(i).events.first?.sources, [.paceforge])
    }

    func testTheSameRideTwiceIsOneRow() {
        var i = input()
        i.rides = [ride(startTs: at(7, 30)), ride(startTs: at(7, 30))]
        XCTAssertEqual(DayTimeline.build(i).events.filter { $0.kind == .workout }.count, 1)
    }

    func testARideCountsAsRecordedData() {
        var i = input()
        i.rides = [ride(startTs: at(7, 30))]
        XCTAssertTrue(DayTimeline.build(i).hasRecordedData)
    }
}
