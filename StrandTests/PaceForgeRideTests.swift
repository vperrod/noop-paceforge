import XCTest
@testable import Strand

/// Bike rides: ride-metrics.json and the stream file decode leniently, a long stream is downsampled to at most
/// 600 points without bridging holes, pauses break the line, and the formats the ride screen shows are exact.
/// All values are made up.
final class PaceForgeRideTests: XCTestCase {
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private let metricsDoc = """
    {"version":1,"generated_at":"2030-03-13T06:00:00","rides":{
      "bike:2030-03-13":{"ride_id":"bike:2030-03-13","date":"2030-03-13","workout":"Synthetic sweet spot","resolution":"1hz",
        "stream":true,"samples":3600,"ftp":250,"duration_s":3600,"avg_power":190,"np":201,"if":0.8,"tss":64,"vi":1.06,"kj":684,
        "kcal_est":660,"avg_hr":148,"ef":1.36,"decoupling":{"pct":3.2,"valid":true,"hr_drift_bpm":4},
        "power_zones":[{"zone":1,"name":"Recovery","lo_w":0,"hi_w":137,"secs":600,"pct":16.7},{"zone":2,"name":"Endurance","lo_w":138,"hi_w":187,"secs":3000,"pct":83.3}],
        "hr_zones":[{"zone":1,"low":90,"high":120,"secs":1200,"pct":33.3},{"zone":2,"low":121,"high":140,"secs":2400,"pct":66.7}],
        "mmp":{"300":260,"5":410,"60":330,"1200":231},
        "laps":[{"n":1,"name":"Warm-up","start_s":0,"end_s":600,"secs":600,"avg_power":140,"pct_ftp":56,"target_power":135,"vs_target_pct":3.7,"avg_hr":120}],
        "compliance":"Synthetic: on plan.","hrr1":{"bpm":28,"kind":"post"},"type":"endurance","summary_line":"Synthetic summary."},
      "bike:2030-03-11":{"ride_id":"bike:2030-03-11","resolution":"240pt","stream":false,"duration_s":2400,"avg_power":150,
        "decoupling":{"pct":null,"valid":false,"hr_drift_bpm":null}}}}
    """

    // MARK: ride-metrics.json

    func testRidesAreListedNewestFirst() {
        XCTAssertEqual(PFRideParse.metrics(json(metricsDoc)).map(\.id), ["bike:2030-03-13", "bike:2030-03-11"])
    }

    func testRideReadsTheKeyNumbers() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        XCTAssertEqual(ride.np, 201)
        XCTAssertEqual(ride.intensityFactor, 0.8)
        XCTAssertEqual(ride.tss, 64)
        XCTAssertEqual(ride.kj, 684)
    }

    func testRideRowLineUsesBikeVocabulary() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        XCTAssertEqual(ride.rowLine, "60 min \u{00B7} avg 190 W \u{00B7} NP 201 W \u{00B7} TSS 64 \u{00B7} avg HR 148 bpm")
    }

    func testRideTextHasNoRunningVocabulary() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        let text = [ride.rowLine, ride.resolutionNote, ride.title].joined(separator: " ").lowercased()
        for word in ["pace", "stride", "spm", "/km", "split"] {
            XCTAssertFalse(text.contains(word), "A ride should not use \"\(word)\".")
        }
    }

    func testMeanMaximalPowerIsSortedByDuration() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        XCTAssertEqual(ride.mmp.map(\.seconds), [5, 60, 300, 1200])
    }

    func testZonesKeepTheirEdgesAndShares() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        XCTAssertEqual(ride.powerZones.map(\.rangeText), ["0\u{2013}137", "138\u{2013}187"])
    }

    func testZoneFractionsComeFromTheSeconds() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        let fractions = PFRideZones.fractions(ride.hrZones)
        XCTAssertEqual(fractions[1], 2.0 / 3.0, accuracy: 0.0001)
    }

    func testZoneFractionsFallBackToThePercentagesWithoutSeconds() {
        let zones = [PFRideZone(zone: 1, secs: 0, pct: 25), PFRideZone(zone: 2, secs: 0, pct: 75)]
        XCTAssertEqual(PFRideZones.fractions(zones), [0.25, 0.75])
    }

    func testLapKeepsItsTargetComparison() throws {
        let lap = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first?.laps.first)
        XCTAssertEqual(lap.vsTargetPct, 3.7)
    }

    func testComplianceTextIsReadFromAStringOrAnObject() {
        XCTAssertEqual(PFRideParse.complianceText(json(#"{"summary":"Synthetic."}"#)), "Synthetic.")
    }

    func testDecouplingShowsItsFigureWhenValid() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        XCTAssertEqual(ride.decoupling?.text, "3.2 %")
    }

    func testDecouplingThatIsNotValidSaysSo() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).last)
        XCTAssertEqual(ride.decoupling?.text, "Not valid")
    }

    func testRideWithNoDecouplingObjectHasNone() {
        let doc = json(#"{"rides":{"bike:2030-03-12":{"ride_id":"bike:2030-03-12"}}}"#)
        XCTAssertNil(PFRideParse.metrics(doc).first?.decoupling)
    }

    func testAbsentDocumentHasNoRides() {
        XCTAssertEqual(PFRideParse.metrics(PFJ(nil)).count, 0)
    }

    // MARK: Resolution

    func testSecondBySecondRideSaysSo() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        XCTAssertEqual(ride.resolutionNote, "second-by-second")
    }

    func testSampleRideSaysSoAndCarriesTheEstimateNote() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).last)
        XCTAssertEqual(ride.resolutionNote, "240-point sample")
        XCTAssertEqual(ride.estimateNote, "Estimated from a 240-point sample")
    }

    func testSecondBySecondRideHasNoEstimateNote() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).first)
        XCTAssertNil(ride.estimateNote)
    }

    func testRideWithStreamFalseHasNoStream() throws {
        let ride = try XCTUnwrap(PFRideParse.metrics(json(metricsDoc)).last)
        XCTAssertFalse(ride.hasStream)
    }

    // MARK: Paths

    func testStreamFileNameReplacesColonsWithDashes() {
        let ride = PFRide(id: "bike:2030-03-13T07:30:00", dateKey: "2030-03-13T07:30:00")
        XCTAssertEqual(ride.streamPath, "data/bike/streams/2030-03-13T07-30-00.json")
    }

    func testAnalysisFileKeepsTheColon() {
        let ride = PFRide(id: "bike:2030-03-13", dateKey: "2030-03-13")
        XCTAssertEqual(ride.analysisPath, "data/analyses/bike:2030-03-13.md")
    }

    func testRideDateIsTheDayPartOfTheKey() {
        let ride = PFRide(id: "bike:2030-03-13T07:30:00", dateKey: "2030-03-13T07:30:00")
        XCTAssertEqual(ride.date, "2030-03-13")
    }

    // MARK: Stream

    private let streamDoc = """
    {"version":1,"hz":1,"ride_id":"bike:2030-03-13","date":"2030-03-13","start_ms":1900000000000,"workout":"Synthetic","ftp":250,
     "t":[0,1,2,3,4,5],"power":[100,110,null,130,140,150],"hr":[90,91,92,null,94,95],"cadence":[80,81,82,83,84,85],
     "speed":[],"distance_m":[],"target_power":[120,120,120,140,140,140],
     "laps":[{"n":1,"secs":3}],"pauses":[{"start_s":2,"end_s":3},[4,5]]}
    """

    func testStreamReadsTheParallelSeriesWithNullsAsGaps() throws {
        let stream = try XCTUnwrap(PFRideParse.stream(json(streamDoc)))
        XCTAssertEqual(stream.power.map { $0 == nil }, [false, false, true, false, false, false])
    }

    func testStreamPadsShortSeriesToTheLongestOne() throws {
        let stream = try XCTUnwrap(PFRideParse.stream(json(streamDoc)))
        XCTAssertEqual(stream.speed.count, 6)
    }

    func testStreamReadsPausesInBothShapes() throws {
        let stream = try XCTUnwrap(PFRideParse.stream(json(streamDoc)))
        XCTAssertEqual(stream.pauses, [PFRidePause(start: 2, end: 3), PFRidePause(start: 4, end: 5)])
    }

    func testStreamWithoutATimeAxisUsesTheSampleRate() throws {
        let stream = try XCTUnwrap(PFRideParse.stream(json(#"{"hz":2,"power":[1,2,3]}"#)))
        XCTAssertEqual(stream.t, [0, 0.5, 1])
    }

    func testEmptyStreamIsNil() {
        XCTAssertNil(PFRideParse.stream(json(#"{"hz":1}"#)))
    }

    // MARK: Downsampling

    func testShortSeriesIsKeptWhole() {
        let points = PFRideChart.downsample(t: [0, 1, 2], values: [1, nil, 3])
        XCTAssertEqual(points, [PFRidePoint(t: 0, v: 1), PFRidePoint(t: 1, v: nil), PFRidePoint(t: 2, v: 3)])
    }

    func testLongSeriesIsCappedAtSixHundredPoints() {
        let t = (0..<7200).map { Double($0) }
        let values: [Double?] = t.map { $0 }
        XCTAssertLessThanOrEqual(PFRideChart.downsample(t: t, values: values).count, 600)
    }

    func testSeriesJustOverTheCapIsStillCapped() {
        let t = (0..<601).map { Double($0) }
        XCTAssertLessThanOrEqual(PFRideChart.downsample(t: t, values: t.map { Optional($0) }).count, 600)
    }

    func testBucketsAreAveraged() {
        let t = (0..<1200).map { Double($0) }
        let values: [Double?] = (0..<1200).map { $0 % 2 == 0 ? 100 : 200 }
        XCTAssertEqual(PFRideChart.downsample(t: t, values: values).first?.v, 150)
    }

    func testBucketWithNoReadingStaysAGap() {
        let t = (0..<1200).map { Double($0) }
        let values: [Double?] = (0..<1200).map { $0 < 2 ? nil : 100 }
        XCTAssertNil(PFRideChart.downsample(t: t, values: values).first?.v)
    }

    func testBucketTimeIsTheMeanOfItsSamples() {
        let t = (0..<1200).map { Double($0) }
        XCTAssertEqual(PFRideChart.downsample(t: t, values: t.map { Optional($0) }).first?.t, 0.5)
    }

    func testDownsamplingNothingGivesNothing() {
        XCTAssertEqual(PFRideChart.downsample(t: [], values: []), [])
    }

    func testChartDataCapsEverySeriesAtSixHundredPoints() {
        var stream = PFRideStream()
        stream.t = (0..<7200).map { Double($0) }
        stream.power = stream.t.map { Optional($0) }
        stream.hr = stream.t.map { Optional($0) }
        stream.cadence = stream.t.map { Optional($0) }
        stream.targetPower = stream.t.map { Optional($0) }
        let data = PFRideChartData(stream)
        XCTAssertEqual([data.power.count, data.hr.count, data.cadence.count, data.target.count].max(), 600)
    }

    func testChartDataFlagsOnlyTheSeriesThatHaveReadings() {
        var stream = PFRideStream()
        stream.t = [0, 1]
        stream.power = [100, 110]
        stream.hr = [nil, nil]
        let data = PFRideChartData(stream)
        XCTAssertEqual([data.hasPower, data.hasHr, data.hasCadence], [true, false, false])
    }

    // MARK: Runs and pauses

    func testGapsSplitTheLine() {
        let points = [PFRidePoint(t: 0, v: 1), PFRidePoint(t: 1, v: nil), PFRidePoint(t: 2, v: 3)]
        XCTAssertEqual(PFRideChart.runs(points, pauses: []).map(\.count), [1, 1])
    }

    func testPointsInsideAPauseAreDropped() {
        let points = (0..<6).map { PFRidePoint(t: Double($0), v: 100) }
        let runs = PFRideChart.runs(points, pauses: [PFRidePause(start: 2, end: 4)])
        XCTAssertEqual(runs.map { $0.map(\.t) }, [[0, 1], [4, 5]])
    }

    func testAPauseBetweenTwoNeighboursSplitsThem() {
        let points = [PFRidePoint(t: 0, v: 1), PFRidePoint(t: 10, v: 2)]
        XCTAssertEqual(PFRideChart.runs(points, pauses: [PFRidePause(start: 4, end: 6)]).count, 2)
    }

    func testNoPausesAndNoGapsIsOneRun() {
        let points = (0..<4).map { PFRidePoint(t: Double($0), v: 5) }
        XCTAssertEqual(PFRideChart.runs(points, pauses: []).count, 1)
    }

    // MARK: Bounds

    func testPowerBoundsStartAtZero() {
        XCTAssertEqual(PFRideChart.bounds([100, nil, 300], zeroBased: true), 0...300)
    }

    func testHeartRateBoundsAreTightWithAMargin() {
        let range = PFRideChart.bounds([100, 140], zeroBased: false)
        XCTAssertEqual(range, 96...144)
    }

    func testBoundsOfNothingAreNil() {
        XCTAssertNil(PFRideChart.bounds([nil, nil], zeroBased: true))
    }

    // MARK: Formats

    func testClockFormatsMinutesAndHours() {
        XCTAssertEqual([PFRideFormat.clock(125), PFRideFormat.clock(3725)], ["2:05", "1:02:05"])
    }

    func testMeanMaximalDurationsReadNaturally() {
        XCTAssertEqual([5, 60, 1200, 3600].map { PFRideFormat.duration($0) }, ["5 s", "1 min", "20 min", "1 h"])
    }

    func testSignedPercentIsNeutral() {
        XCTAssertEqual([4.2, -1.8, 0.2].map { PFRideFormat.signedPercent($0) }, ["+4 %", "\u{2212}2 %", "0 %"])
    }

    // MARK: day-events.json

    private let eventsDoc = """
    {"events":[
      {"kind":"workout","date":"2030-03-13","start":"2030-03-13T07:30:00","end":"2030-03-13T08:30:00","title":"Synthetic sweet spot",
       "activity_id":null,"ride_id":"bike:2030-03-13","sport":"indoor_cycling","avg_power":190,"np":201,"tss":64,"avg_hr":148,"stream":true},
      {"kind":"workout","date":"2030-03-13","title":"Synthetic run","activity_id":9000000009},
      {"kind":"planned","date":"2030-03-13","session_id":"s-wed"}]}
    """

    func testOnlyRideRowsAreRides() {
        XCTAssertEqual(PFRideParse.dayRideEvents(json(eventsDoc)).map(\.rideId), ["bike:2030-03-13"])
    }

    func testRideEventKeepsItsFigures() throws {
        let event = try XCTUnwrap(PFRideParse.dayRideEvents(json(eventsDoc)).first)
        XCTAssertEqual(event.np, 201)
        XCTAssertNotNil(event.startTs)
    }
}
