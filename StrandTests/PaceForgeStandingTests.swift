import XCTest
@testable import Strand

/// "Where you stand": standing.json decodes leniently (every field optional), the five-segment band bar and
/// the summary strip map the way the screens draw them, the not-applicable profile shows its note, and the
/// Telegram phrase comes from the test's own text. All values are made up.
final class PaceForgeStandingTests: XCTestCase {
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private let doc = """
    {"generated_at":"2030-03-13T06:00:00","profile":{"age":40,"sex":"m","height_cm":180,"weight_kg":80,
      "norms_pack":"synthetic-pack","applicable":true,"note":"Synthetic note."},
     "domains":[
      {"id":"heart_lungs","title":"Heart and lungs","metrics":[
        {"id":"rhr","label":"Resting heart rate","value":58,"display":"58","unit":"bpm","band":3,"band_label":"Good",
         "norm":{"poor":"over 80","average":"70 to 80","good":"60 to 70","very_good":"50 to 60","elite":"under 50"},
         "source":{"tag":"PR","label":"Synthetic source","url":"https://example.invalid/a"},
         "confidence":"low","why":"Synthetic why.","trend":{"direction":"down","change":-2.4,"window_days":30,"improving":true},
         "plan_id":"p1","note":null},
        {"id":"vo2","label":"VO2 max","value":null,"display":null,"unit":"ml/kg/min","band":null,"band_label":"Not rated"}
      ]},
      {"id":"strength_power","metrics":[
        {"id":"grip","label":"Grip strength","value":52,"display":"52 kg","unit":"kg","band":5,"confidence":"high"}
      ]}],
     "summary":{"counts":{"poor":0,"average":1,"good":2,"very_good":0,"elite":1,"not_rated":1},
       "strongest":["grip","rhr","missing","vo2"],"focus":["rhr"],"unrated":["vo2"]},
     "plans_intro":"Synthetic plans intro.",
     "plans":[{"id":"p1","title":"Synthetic plan","why":"Why","steps":["One","Two",{"text":"Three"}],"measure":"Measure",
       "dont":"Do not","evidence":"Evidence","timeframe":"8 weeks"}],
     "test_day":{"intro":"Synthetic intro.","tests":[
       {"id":"pushups","label":"Push-ups","unit":"reps","how":"Max in one set. Telegram e.g. \\"push-ups 35\\"","norm_note":"Norm note",
        "logged":{"value":35,"date":"2030-03-01"}},
       {"id":"grip","label":"Grip","unit":"kg","how":"grip 52 kg","norm_note":null,"logged":null}]}}
    """

    // MARK: Parsing

    func testMetricReadsValueBandNormSourceTrendAndPlan() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        let rhr = try XCTUnwrap(standing.metric("rhr"))
        XCTAssertEqual(rhr.valueText, "58 bpm")
        XCTAssertEqual(rhr.band, 3)
        XCTAssertEqual(rhr.bandName, "Good")
        XCTAssertEqual(rhr.norm?.rows.count, 5)
        XCTAssertEqual(rhr.source?.tag, "PR")
        XCTAssertEqual(rhr.planId, "p1")
        XCTAssertTrue(rhr.isLowConfidence)
        XCTAssertEqual(rhr.trend?.improving, true)
    }

    func testDisplayThatAlreadyCarriesTheUnitIsNotShownTwice() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertEqual(standing.metric("grip")?.valueText, "52 kg")
    }

    func testUnratedMetricHasNoBandAndSaysNotRated() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        let vo2 = try XCTUnwrap(standing.metric("vo2"))
        XCTAssertNil(vo2.band)
        XCTAssertEqual(vo2.bandName, "Not rated")
    }

    func testAMetricWithNoValueShowsADash() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertEqual(standing.metric("vo2")?.valueText, "\u{2014}")
    }

    func testDomainWithoutATitleGetsOneFromItsId() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertEqual(standing.domains.last?.title, "Strength power")
    }

    func testOutOfRangeBandReadsAsNotRated() {
        let standing = PFStandingParse.standing(json(#"{"domains":[{"id":"d","metrics":[{"id":"m","label":"M","band":9}]}]}"#))
        XCTAssertNil(standing?.metric("m")?.band)
    }

    func testPlanStepsAcceptPlainStringsAndObjects() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertEqual(standing.plan("p1")?.steps, ["One", "Two", "Three"])
    }

    func testAbsentDocumentIsNil() {
        XCTAssertNil(PFStandingParse.standing(PFJ(nil)))
    }

    func testEmptyObjectIsNil() {
        XCTAssertNil(PFStandingParse.standing(json("{}")))
    }

    func testStrongestAndFocusChipsKeepTheOrderAndSkipUnknownIds() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertEqual(standing.strongestTop.map(\.id), ["grip", "rhr", "vo2"])
        XCTAssertEqual(standing.focusTop.map(\.id), ["rhr"])
    }

    func testStrongestChipsAreCappedAtThree() {
        let text = #"{"domains":[{"id":"d","metrics":[{"id":"a","label":"A"},{"id":"b","label":"B"},{"id":"c","label":"C"},{"id":"e","label":"E"}]}],"summary":{"strongest":["a","b","c","e"]}}"#
        XCTAssertEqual(PFStandingParse.standing(json(text))?.strongestTop.map(\.id), ["a", "b", "c"])
    }

    // MARK: Not applicable

    func testNotApplicableProfileKeepsItsNoteAndHidesNothingElseIsNeeded() throws {
        let text = #"{"profile":{"applicable":false,"note":"Norms need sex and age."},"domains":[]}"#
        let standing = try XCTUnwrap(PFStandingParse.standing(json(text)))
        XCTAssertFalse(standing.isApplicable)
        XCTAssertEqual(standing.profile?.note, "Norms need sex and age.")
        XCTAssertTrue(standing.hasContent)
    }

    func testAbsentApplicableFlagMeansApplicable() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(#"{"profile":{"age":40},"domains":[]}"#)))
        XCTAssertTrue(standing.isApplicable)
    }

    // MARK: Band bar

    func testBandThreeFillsTwoSegmentsMarksTheThirdAndLeavesTwoAhead() {
        XCTAssertEqual(PFBand.segments(for: 3), [.reached, .reached, .current, .ahead, .ahead])
    }

    func testBandOneMarksTheFirstSegmentOnly() {
        XCTAssertEqual(PFBand.segments(for: 1), [.current, .ahead, .ahead, .ahead, .ahead])
    }

    func testBandFiveFillsFourAndMarksTheLast() {
        XCTAssertEqual(PFBand.segments(for: 5), [.reached, .reached, .reached, .reached, .current])
    }

    func testNoBandIsFiveUnratedSegments() {
        XCTAssertEqual(PFBand.segments(for: nil), Array(repeating: PFBand.Segment.unrated, count: 5))
    }

    func testBandZeroIsUnrated() {
        XCTAssertEqual(PFBand.segments(for: 0), Array(repeating: PFBand.Segment.unrated, count: 5))
    }

    func testBandNamesAreTheNeutralFiveAndServerLabelWins() {
        XCTAssertEqual((1...5).map { PFBand.name(band: $0, serverLabel: nil) },
                       ["Poor", "Average", "Good", "Very good", "Elite"])
        XCTAssertEqual(PFBand.name(band: 2, serverLabel: "Typical"), "Typical")
    }

    func testAccessibilityTextNamesTheBandAndItsPlaceOnTheScale() {
        XCTAssertEqual(PFBand.accessibilityText(label: "Resting heart rate", value: "58 bpm", band: 3, serverLabel: "Good"),
                       "Resting heart rate, 58 bpm. Good, band 3 of 5.")
    }

    func testAccessibilityTextForAnUnratedMetricSaysNotRated() {
        XCTAssertEqual(PFBand.accessibilityText(label: "VO2 max", value: "\u{2014}", band: nil, serverLabel: nil),
                       "VO2 max, \u{2014}. Not rated.")
    }

    // MARK: Summary strip

    func testStripFractionsAreEachCountsShareOfTheTotal() {
        XCTAssertEqual(PFBand.stripFractions(counts: [0, 1, 2, 0, 1, 0]), [0, 0.25, 0.5, 0, 0.25, 0])
    }

    func testStripFractionsOfNothingAreAllZero() {
        XCTAssertEqual(PFBand.stripFractions(counts: [0, 0, 0, 0, 0, 0]), [0, 0, 0, 0, 0, 0])
    }

    func testSummaryCountsFollowTheStripOrder() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertEqual(standing.summary?.counts, [0, 1, 2, 0, 1, 1])
    }

    // MARK: Norm table

    func testNormTableListsEveryBandLowestFirst() throws {
        let rows = try XCTUnwrap(PFStandingParse.standing(json(doc))?.metric("rhr")?.norm?.rows)
        XCTAssertEqual(rows.map(\.name), ["Poor", "Average", "Good", "Very good", "Elite"])
    }

    func testNormTableLeavesOutBandsTheServerSentNoTextFor() {
        let text = #"{"domains":[{"id":"d","metrics":[{"id":"m","label":"M","norm":{"poor":"a","elite":"b"}}]}]}"#
        XCTAssertEqual(PFStandingParse.standing(json(text))?.metric("m")?.norm?.rows.map(\.band), [1, 5])
    }

    // MARK: Trend

    func testTrendTextIsNeutralAndNamesTheWindow() {
        XCTAssertEqual(PFStandingTrend(direction: "down", change: -2.4, windowDays: 30, improving: true).text,
                       "Down 2.4 over 30 days")
    }

    func testTrendArrowFollowsTheDirection() {
        XCTAssertEqual(PFStandingTrend(direction: "up", change: 1, windowDays: nil, improving: nil).symbol, "arrow.up.right")
    }

    func testUnknownDirectionReadsAsFlat() {
        XCTAssertEqual(PFStandingTrend(direction: "steady", change: 0, windowDays: 14, improving: nil).text, "Flat over 14 days")
    }

    // MARK: Test day and the Telegram phrase

    func testPhraseIsTheQuotedTextAfterEg() {
        XCTAssertEqual(PFTestPhrase.telegram(from: #"Max in one set. Telegram e.g. "push-ups 35""#), "push-ups 35")
    }

    func testPhraseAcceptsCurlyQuotes() {
        XCTAssertEqual(PFTestPhrase.telegram(from: "Say \u{201C}squat 140 x 5\u{201D} in Telegram"), "squat 140 x 5")
    }

    func testShortHowWithNoQuotesIsThePhraseItself() {
        XCTAssertEqual(PFTestPhrase.telegram(from: "grip 52 kg"), "grip 52 kg")
    }

    func testLongHowWithNoQuotesGivesNoPhrase() {
        let how = String(repeating: "Do the test carefully. ", count: 5)
        XCTAssertNil(PFTestPhrase.telegram(from: how))
    }

    func testNoHowGivesNoPhrase() {
        XCTAssertNil(PFTestPhrase.telegram(from: nil))
    }

    func testTestDayKeepsTheLoggedValueAndDate() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        let test = try XCTUnwrap(standing.testDay?.tests.first)
        XCTAssertEqual(test.logged?.value, 35)
        XCTAssertEqual(test.logged?.date, "2030-03-01")
    }

    func testTestDayEntryWithNullLoggedHasNone() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertNil(standing.testDay?.tests.last?.logged)
    }

    func testTestDayIntroIsKeptVerbatim() throws {
        let standing = try XCTUnwrap(PFStandingParse.standing(json(doc)))
        XCTAssertEqual(standing.testDay?.intro, "Synthetic intro.")
    }
}
