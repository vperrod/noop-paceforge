import XCTest
@testable import Strand

/// The "Where you stand", Garmin recovery and ride widgets: what the app leaves in the summary for them, and what
/// Settings > Hide numbers takes out of it. Every document is a made-up one in the shape the server serves.
final class PaceForgeGlanceTests: XCTestCase {
    private func standing(_ text: String) -> PFStanding? { PFStandingParse.standing(PFJ(data: Data(text.utf8))) }

    private let scorecard = """
    {"profile":{"applicable":true},"generated_at":"2026-10-14T07:00:00",
     "domains":[{"id":"body","title":"Body","metrics":[
        {"id":"body_fat","label":"Body fat","value":24,"display":"24 %","band":2},
        {"id":"vo2max","label":"VO2 max","value":52,"unit":"ml/kg/min","band":4,"band_label":"Very good"},
        {"id":"sleep_duration","label":"Sleep duration","value":6.8,"unit":"h","band":2},
        {"id":"sit_reach","label":"Sit and reach","band":null}]}],
     "summary":{"counts":{},"strongest":["vo2max"],"focus":["body_fat","sleep_duration"]}}
    """

    private func glance() -> PFStandingGlance? { PFGlanceBuilder.standing(standing(scorecard)) }

    // MARK: Where you stand

    func testTheStrongestMetricCarriesItsLabelBandAndValue() {
        let item = glance()?.strongest.first
        XCTAssertEqual([item?.label, item?.bandName, item?.value], ["VO2 max", "Very good", "52 ml/kg/min"])
    }

    func testTheFocusMetricsKeepTheServersOrder() {
        XCTAssertEqual(glance()?.focus.map(\.id), ["body_fat", "sleep_duration"])
    }

    func testABodyCompositionMetricNamesItsSwitch() {
        XCTAssertEqual(glance()?.focus.first?.hideKind, "body")
    }

    func testASleepMetricNamesTheScoresSwitch() {
        XCTAssertEqual(glance()?.focus.last?.hideKind, "scores")
    }

    func testAMetricNoSwitchCoversNamesNone() {
        XCTAssertNil(glance()?.strongest.first?.hideKind)
    }

    func testTheScorecardDayIsKept() {
        XCTAssertEqual(glance()?.date, "2026-10-14")
    }

    func testAScorecardThatDoesNotApplyHasNoGlance() {
        XCTAssertNil(PFGlanceBuilder.standing(standing(#"{"profile":{"applicable":false,"note":"Norms need sex and age."}}"#)))
    }

    func testNoScorecardHasNoGlance() {
        XCTAssertNil(PFGlanceBuilder.standing(nil))
    }

    func testHidingTheBodySwitchReplacesOnlyTheBodyValue() {
        let hidden = glance()?.redacted(scores: false, body: true)
        XCTAssertEqual(hidden?.focus.map(\.value), ["Hidden", "6.8 h"])
    }

    func testHidingTheScoresSwitchReplacesOnlyTheSleepValue() {
        let hidden = glance()?.redacted(scores: true, body: false)
        XCTAssertEqual(hidden?.focus.map(\.value), ["24 %", "Hidden"])
    }

    func testAnUncoveredMetricKeepsItsValueWhateverIsHidden() {
        XCTAssertEqual(glance()?.redacted(scores: true, body: true).strongest.first?.value, "52 ml/kg/min")
    }

    func testHidingKeepsTheBandsAndLabels() {
        XCTAssertEqual(glance()?.redacted(scores: true, body: true).focus.map(\.bandName), ["Average", "Average"])
    }

    func testNothingHiddenChangesNothing() {
        XCTAssertEqual(glance()?.redacted(scores: false, body: false), glance())
    }

    func testTheGlanceSurvivesTheStoredJson() throws {
        let original = try XCTUnwrap(glance())
        XCTAssertEqual(try JSONDecoder().decode(PFStandingGlance.self, from: JSONEncoder().encode(original)), original)
    }

    // MARK: Garmin recovery

    private func activity(_ start: String?, _ json: String?) -> PFGlanceBuilder.Activity {
        PFGlanceBuilder.Activity(name: "Session \(start ?? "")", startTime: start,
                                 hrrGarmin: json.flatMap { PFHRRGarmin.parse(PFJ(data: Data($0.utf8))) })
    }

    func testTheNewestActivityWithGarminRecoveryWins() {
        let glance = PFGlanceBuilder.garminRecovery([
            activity("2026-10-10T07:00:00", #"{"drop_bpm":32,"hr_2min":116,"stop_bpm":148}"#),
            activity("2026-10-12T07:00:00", #"{"drop_bpm":46,"hr_2min":103,"stop_bpm":149}"#),
            activity("2026-10-13T07:00:00", nil)])
        XCTAssertEqual(glance?.dropBpm, 46)
    }

    func testTheRecoveryGlanceUsesTheCardsWords() {
        let glance = PFGlanceBuilder.garminRecovery([activity("2026-10-12T07:00:00", #"{"drop_bpm":46,"hr_2min":103,"stop_bpm":149}"#)])
        XCTAssertEqual([glance?.headline, glance?.detail],
                       ["Garmin recovery heart rate: -46 bpm in 2 minutes", "149 at the stop, 103 two minutes later"])
    }

    func testTheRecoveryGlanceNamesTheSessionAndItsDay() {
        let glance = PFGlanceBuilder.garminRecovery([activity("2026-10-12T07:00:00", #"{"drop_bpm":46}"#)])
        XCTAssertEqual([glance?.sessionName, glance?.date], ["Session 2026-10-12T07:00:00", "2026-10-12"])
    }

    func testNoActivityWithGarminRecoveryHasNoGlance() {
        XCTAssertNil(PFGlanceBuilder.garminRecovery([activity("2026-10-12T07:00:00", nil)]))
    }

    // MARK: Rides

    private func rides(_ text: String) -> [PFRide] { PFRideParse.metrics(PFJ(data: Data(text.utf8))) }

    private let rideFile = """
    {"rides":{
      "bike:2026-10-01":{"workout":"Synthetic endurance","duration_s":3600,"avg_power":180,"np":190,"tss":60,"avg_hr":140},
      "bike:2026-10-08":{"workout":"Synthetic tempo","duration_s":3900,"avg_power":200,"np":210,"tss":75,"avg_hr":150}}}
    """

    private func session(_ name: String, _ date: String, sport: String? = "cycling", open: Bool = true) -> PFGlanceBuilder.Session {
        PFGlanceBuilder.Session(name: name, sport: sport, kind: nil, date: date, isOpen: open, detail: "40 km", target: "190 W")
    }

    func testTheLastRideIsTheNewestOne() {
        let glance = PFGlanceBuilder.rides(rides(rideFile), sessions: [], today: "2026-10-14")
        XCTAssertEqual([glance?.last?.title, glance?.last?.date], ["Synthetic tempo", "2026-10-08"])
    }

    func testTheLastRideCarriesPowerTrainingStressAndHeartRate() {
        let last = PFGlanceBuilder.rides(rides(rideFile), sessions: [], today: "2026-10-14")?.last
        XCTAssertEqual([last?.avgPower, last?.tss, last?.avgHr], [200, 75, 150])
    }

    func testTheNextRideIsTheEarliestOpenBikeSessionFromToday() {
        let glance = PFGlanceBuilder.rides([], sessions: [session("Later", "2026-10-18"), session("Soon", "2026-10-15"),
                                                          session("Past", "2026-10-10")], today: "2026-10-14")
        XCTAssertEqual(glance?.next?.name, "Soon")
    }

    func testTodaysOpenRideIsTheNextRide() {
        let glance = PFGlanceBuilder.rides([], sessions: [session("Today", "2026-10-14")], today: "2026-10-14")
        XCTAssertEqual(glance?.next?.name, "Today")
    }

    func testADoneRideIsNotTheNextRide() {
        let glance = PFGlanceBuilder.rides([], sessions: [session("Done", "2026-10-15", open: false)], today: "2026-10-14")
        XCTAssertNil(glance)
    }

    func testARunIsNotTheNextRide() {
        XCTAssertNil(PFGlanceBuilder.rides([], sessions: [session("Run", "2026-10-15", sport: "running")], today: "2026-10-14"))
    }

    func testBikeSportsAreRecognisedByName() {
        XCTAssertEqual(["indoor_cycling", "cycling", "bike", "Virtual Ride", "running", nil].map { PFGlanceBuilder.isRide(sport: $0, kind: nil) },
                       [true, true, true, true, false, false])
    }

    func testNoRideAndNoPlanHasNoGlance() {
        XCTAssertNil(PFGlanceBuilder.rides([], sessions: [], today: "2026-10-14"))
    }

    func testHidingTheScoresTakesTheTrainingStressOutOfTheLastRide() {
        let glance = PFGlanceBuilder.rides(rides(rideFile), sessions: [], today: "2026-10-14")
        XCTAssertNil(glance?.redacted(scores: true, today: "2026-10-14").last?.tss)
    }

    func testHidingTheScoresKeepsThePowerOfTheLastRide() {
        let glance = PFGlanceBuilder.rides(rides(rideFile), sessions: [], today: "2026-10-14")
        XCTAssertEqual(glance?.redacted(scores: true, today: "2026-10-14").last?.avgPower, 200)
    }

    func testTheTrainingStressStaysWhenTheScoresAreShown() {
        let glance = PFGlanceBuilder.rides(rides(rideFile), sessions: [], today: "2026-10-14")
        XCTAssertEqual(glance?.redacted(scores: false, today: "2026-10-14").last?.tss, 75)
    }

    func testANextRideWhoseDayHasGoneByIsDropped() {
        let glance = PFRideGlance(last: nil, next: PFRideGlance.Next(name: "Old plan", date: "2026-10-13"))
        XCTAssertNil(glance.redacted(scores: false, today: "2026-10-14").next)
    }
}
