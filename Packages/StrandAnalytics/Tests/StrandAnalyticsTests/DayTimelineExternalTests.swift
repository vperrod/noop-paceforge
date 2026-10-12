import XCTest
@testable import StrandAnalytics

/// What an outside source (PaceForge) adds to My Day: a planned session with a clock time, a timed weigh-in,
/// a niggle note, and Garmin's Body Battery and stress as curves of their own. All values are made up.
final class DayTimelineExternalTests: XCTestCase {

    /// 2026-06-10 00:00 UTC.
    private let day0 = 1_781_049_600

    private func at(_ hour: Int, _ minute: Int = 0) -> Int { day0 + hour * 3600 + minute * 60 }
    private func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

    /// A finished plain day unless `now` says otherwise.
    private func input(now: Int? = nil) -> DayTimeline.Input {
        DayTimeline.Input(dayStart: date(day0), dayEnd: date(day0 + 86_400), now: date(now ?? day0 + 2 * 86_400))
    }

    // MARK: Planned sessions with a slot

    func testAPlannedSessionWithASlotIsATimedRow() {
        var i = input(now: at(6))
        i.planned = [.init(id: "p", title: "Intervals", startTs: at(7, 30), durationMin: 55)]
        XCTAssertEqual(DayTimeline.build(i).events.first { $0.kind == .planned }?.isUntimed, false)
    }

    func testAPlannedSessionWithoutASlotStaysUntimed() {
        var i = input(now: at(6))
        i.planned = [.init(id: "p", title: "Intervals", durationMin: 55)]
        XCTAssertEqual(DayTimeline.build(i).events.first { $0.kind == .planned }?.isUntimed, true)
    }

    func testAPlannedSlotRunsForTheSessionsDuration() {
        var i = input(now: at(6))
        i.planned = [.init(id: "p", title: "Intervals", startTs: at(7, 30), durationMin: 55)]
        XCTAssertEqual(DayTimeline.build(i).events.first { $0.kind == .planned }?.end, date(at(8, 25)))
    }

    // MARK: Weigh-ins

    func testATimedWeighInIsListedAtItsTime() {
        var i = input()
        i.weighIns = [.init(ts: at(6, 45), kg: 78.7, source: .paceforge)]
        XCTAssertEqual(DayTimeline.build(i).events.first { $0.kind == .weighIn }?.start, date(at(6, 45)))
    }

    // MARK: Notes

    func testANiggleWithATimeIsATimedNote() {
        var i = input()
        i.notes = [.init(id: "n1", ts: at(9, 10), title: "Niggle", subtitle: "Left calf \u{00B7} 2 of 5")]
        XCTAssertEqual(DayTimeline.build(i).events.first { $0.id == "note-n1" }?.isUntimed, false)
    }

    func testANiggleWithoutATimeIsListedAllDay() {
        var i = input()
        i.notes = [.init(id: "n1", ts: nil, title: "Niggle")]
        XCTAssertEqual(DayTimeline.build(i).events.first { $0.id == "note-n1" }?.isUntimed, true)
    }

    func testANiggleCarriesThePaceForgeBadge() {
        var i = input()
        i.notes = [.init(id: "n1", ts: nil, title: "Niggle")]
        XCTAssertEqual(DayTimeline.build(i).events.first { $0.id == "note-n1" }?.sources, [.paceforge])
    }

    // MARK: Energy and Garmin stress

    func testEnergyKeepsOnlyTheShownDaysReadingsInTimeOrder() {
        var i = input()
        i.energy = [.init(ts: at(9), value: 70), .init(ts: at(1), value: 40), .init(ts: day0 - 3600, value: 20),
                    .init(ts: day0 + 86_400 + 60, value: 90)]
        XCTAssertEqual(DayTimeline.build(i).energy.map(\.value), [40, 70])
    }

    func testNothingIsDrawnPastNow() {
        var i = input(now: at(8))
        i.energy = [.init(ts: at(7), value: 40), .init(ts: at(9), value: 70)]
        XCTAssertEqual(DayTimeline.build(i).energy.map(\.value), [40])
    }

    func testGarminStressIsItsOwnCurveNotNoopsStress() {
        var i = input()
        i.stress = [.init(ts: at(10, 30), level: 1.2)]
        i.garminStress = [.init(ts: at(10), value: 35)]
        let timeline = DayTimeline.build(i)
        XCTAssertEqual([timeline.stress.count, timeline.garminStress.count], [1, 1])
    }

    func testAnEmptyDayHasNoOutsideCurves() {
        let timeline = DayTimeline.build(input())
        XCTAssertEqual([timeline.energy.count, timeline.garminStress.count], [0, 0])
    }

    func testTheLastRechargeIsKeptEvenWhenItStartedTheNightBefore() {
        var i = input()
        i.recharge = .init(startTs: day0 - 7200, endTs: at(6), from: 22, to: 71, minutes: 480)
        XCTAssertEqual(DayTimeline.build(i).recharge?.startTs, day0 - 7200)
    }

    // MARK: Recharge text

    func testTheRechargeLineNamesTheSpanTheLevelsAndTheLength() {
        let recharge = DayTimeline.Recharge(startTs: 100, endTs: 200, from: 22, to: 71, minutes: 480)
        XCTAssertEqual(recharge.text { "t\($0)" }, "Last recharge t100\u{2013}t200 \u{00B7} 22 \u{2192} 71 \u{00B7} 8h 00m")
    }

    func testARechargeWithOnlyAnEndStillReads() {
        let recharge = DayTimeline.Recharge(startTs: nil, endTs: 200, from: nil, to: 55, minutes: nil)
        XCTAssertEqual(recharge.text { "t\($0)" }, "Last recharge ended t200 \u{00B7} to 55")
    }

    func testARechargeWithNothingKnownHasNoLine() {
        XCTAssertNil(DayTimeline.Recharge(startTs: nil, endTs: nil, from: nil, to: nil, minutes: nil).text { "t\($0)" })
    }
}
