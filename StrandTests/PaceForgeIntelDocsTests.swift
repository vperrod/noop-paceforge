import XCTest
@testable import Strand

/// The five Phase 4 documents (healthspan, journal impact, highlights, monthly report, my plan): decoding of the served shapes
/// with missing keys and `available: false`, the range and pace wording, the driver bar, the Healthspan weeks kept on the phone,
/// the impact bars, the streak chip and the "5 days left" line. Every figure is made up.
final class PaceForgeIntelDocsTests: XCTestCase {

    // MARK: Fixtures

    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    /// One document root wrapping a single item, as the server writes it.
    private func wrap(_ id: String, metric: String, available: Bool = true, extra: String = "") -> PFJ {
        json("""
        {"version": 1, "generated_at": "2030-03-13T08:00:00+00:00", "as_of": "2030-03-13", "order": ["\(id)"],
         "items": {"\(id)": {"id": "\(id)", "title": "Synthetic", "available": \(available), "metric": \(metric),
           "status": {"label": "on track", "scale": ["behind", "on track", "done"], "reason": null},
           "meaning": "Synthetic meaning.", "actions": [], "confidence": "medium", "data_note": "Synthetic note.",
           "source": ["Garmin", "PaceForge"]\(extra)}}}
        """)
    }

    private let healthspanMetric = """
    {"as_of": "2030-03-13", "label": "Our calculation of the published WHOOP Healthspan method, not WHOOP's number.",
     "age": 40.0, "sex": "male", "window_days": 182, "inputs_available": 9, "inputs_total": 9, "missing": [],
     "body_age": {"low": 35.2, "high": 37.9, "mid": 37, "text": "35 to 38", "years_vs_age": {"low": -4.8, "high": -2.1, "mid": -3.4}},
     "pace": {"available": true, "reason": null, "week": "2030-W11", "computed_on": "2030-03-13", "carried": false,
       "value": -0.6, "low": -1.0, "high": 2.2, "label": "reversing", "range": [-1.0, 3.0], "basis": "synthetic",
       "metrics": [{"key": "sleep_duration", "label": "Sleep duration", "years_6m": 0.4, "years_30d": 0.9},
                   {"key": "vo2max", "label": "VO2max", "years_6m": -3.5, "years_30d": -3.6}]},
     "drivers": [
       {"key": "vo2max", "label": "VO2max", "unit": "ml/kg/min", "source": "Garmin", "target_text": "39 or more", "note": "synthetic",
        "value": 54.3, "value_text": "54.3 ml/kg/min", "n": 182, "coverage": 1.0, "status": "meets", "years": -3.5,
        "years_low": -4.6, "years_high": -2.4,
        "action": {"id": "healthspan_vo2max", "text": "Keep your intervals.", "why": "Synthetic reason.",
                   "effort": {"value": 0, "unit": "min", "label": "no extra time"}, "impact": 5, "topic": "healthspan", "tags": []}},
       {"key": "sleep_duration", "label": "Sleep duration", "unit": "h", "source": "Garmin", "target_text": "7 to 9 h", "value": 6.4,
        "value_text": "6.4 h", "coverage": 0.98, "status": "short", "years": 0.4, "years_low": 0.2, "years_high": 0.6, "action": null},
       {"key": "steps", "label": "Daily steps", "status": "unknown", "years": null}],
     "assumptions": ["Synthetic assumption one.", "Synthetic assumption two."]}
    """

    private func healthspan() -> PFHealthspan? {
        PFIntelDocsParse.state(wrap("healthspan", metric: healthspanMetric), id: PFDocID.healthspan, PFIntelDocsParse.healthspan).value
    }

    // MARK: Healthspan decoding

    func testHealthspanBodyAgeRangeAndYearsVsAge() throws {
        let h = try XCTUnwrap(healthspan())
        XCTAssertEqual(h.bodyAge?.yearsVsAge, PFYearsRange(low: -4.8, high: -2.1, mid: -3.4))
    }

    func testHealthspanPaceWeekAndRange() throws {
        let pace = try XCTUnwrap(healthspan()?.pace)
        XCTAssertEqual([pace.week ?? "", "\(pace.value ?? 0)", "\(pace.rangeLow)", "\(pace.rangeHigh)"], ["2030-W11", "-0.6", "-1.0", "3.0"])
    }

    func testHealthspanDriversKeepTheirOrderAndStatus() throws {
        let drivers = try XCTUnwrap(healthspan()?.drivers)
        XCTAssertEqual(drivers.map { "\($0.key):\($0.status)" }, ["vo2max:meets", "sleep_duration:short", "steps:unknown"])
    }

    func testHealthspanDriverActionCarriesReasonAndTimeCost() throws {
        let action = try XCTUnwrap(healthspan()?.drivers.first?.action)
        XCTAssertEqual([action.why ?? "", action.effort?.text ?? ""], ["Synthetic reason.", "no extra time"])
    }

    func testHealthspanUnknownDriverHasNoYears() throws {
        let steps = try XCTUnwrap(healthspan()?.drivers.last)
        XCTAssertTrue(steps.isUnknown)
    }

    func testHealthspanAssumptionsAreKept() throws {
        XCTAssertEqual(healthspan()?.assumptions.count, 2)
    }

    func testHealthspanWithoutBodyAgeOrPaceOrDriversIsNotUsable() {
        let state = PFIntelDocsParse.state(wrap("healthspan", metric: "{\"as_of\": \"2030-03-13\"}"), id: PFDocID.healthspan, PFIntelDocsParse.healthspan)
        XCTAssertNil(state.value)
    }

    func testHealthspanUnusableMetricIsUnavailableWithAReason() {
        let state = PFIntelDocsParse.state(wrap("healthspan", metric: "{\"as_of\": \"2030-03-13\"}"), id: PFDocID.healthspan, PFIntelDocsParse.healthspan)
        XCTAssertEqual(state.reason, "The document has no usable figures yet.")
    }

    func testUnavailableItemCarriesTheServersReason() {
        let doc = json("""
        {"version": 1, "as_of": "2030-03-13", "order": ["healthspan"],
         "items": {"healthspan": {"id": "healthspan", "title": "Body age and pace", "available": false, "metric": {},
           "meaning": "Needs 6 of the 9 metrics; 4 so far.", "actions": [], "source": []}}}
        """)
        XCTAssertEqual(PFIntelDocsParse.state(doc, id: PFDocID.healthspan, PFIntelDocsParse.healthspan).reason,
                       "Needs 6 of the 9 metrics; 4 so far.")
    }

    func testMissingDocumentIsMissing() {
        XCTAssertTrue(PFIntelDocsParse.state(PFJ(nil), id: PFDocID.healthspan, PFIntelDocsParse.healthspan).isMissing)
    }

    func testDocumentWithoutItsItemFallsBackToTheFirstItemInOrder() {
        let doc = json("""
        {"version": 1, "as_of": "2030-03-13", "order": ["renamed"],
         "items": {"renamed": {"id": "renamed", "title": "x", "available": true, "metric": \(healthspanMetric), "source": []}}}
        """)
        XCTAssertNotNil(PFIntelDocsParse.state(doc, id: PFDocID.healthspan, PFIntelDocsParse.healthspan).value)
    }

    func testSourcesAreKeptOnTheItem() {
        let state = PFIntelDocsParse.state(wrap("healthspan", metric: healthspanMetric), id: PFDocID.healthspan, PFIntelDocsParse.healthspan)
        XCTAssertEqual(state.item?.sourceText, "Garmin \u{00B7} PaceForge")
    }

    func testAllFiveDocumentsMissingMeansEmpty() {
        let docs = PFIntelDocsParse.docs(healthspan: PFJ(nil), journalImpact: PFJ(nil), highlights: PFJ(nil),
                                         monthlyReport: PFJ(nil), myPlan: PFJ(nil))
        XCTAssertTrue(docs.isEmpty)
    }

    // MARK: Range and pace wording

    func testBodyAgeRangeTextUsesAnEnDash() {
        XCTAssertEqual(PFHealthspanFormat.rangeText(low: 35.2, high: 37.9), "35\u{2013}38")
    }

    func testBodyAgeRangeThatRoundsToOneNumberIsWidened() {
        XCTAssertEqual(PFHealthspanFormat.rangeText(low: 36.6, high: 37.3), "36\u{2013}38")
    }

    func testBodyAgeRangeOfOnePointIsNeverASingleNumber() {
        XCTAssertEqual(PFHealthspanFormat.rangeText(low: 37.0, high: 37.0), "37\u{2013}38")
    }

    func testYoungerRangeReadsFromTheSmallerGapToTheLarger() {
        XCTAssertEqual(PFHealthspanFormat.ageVerdict(PFYearsRange(low: -5.8, high: -3.1, mid: -4.4)).text, "3 to 6 years younger")
    }

    func testYoungerRangeHasTheYoungerDirection() {
        XCTAssertEqual(PFHealthspanFormat.ageVerdict(PFYearsRange(low: -5.8, high: -3.1, mid: nil)).direction, .younger)
    }

    func testOlderRangeReadsFromTheSmallerGapToTheLarger() {
        XCTAssertEqual(PFHealthspanFormat.ageVerdict(PFYearsRange(low: 1.2, high: 3.4, mid: nil)).text, "1 to 3 years older")
    }

    func testRangeAcrossZeroReadsAboutYourAge() {
        XCTAssertEqual(PFHealthspanFormat.ageVerdict(PFYearsRange(low: -1.6, high: 2.2, mid: nil)).text,
                       "about your age (\u{2212}2 to +2 years)")
    }

    func testRangeAcrossZeroHasTheAboutRightDirection() {
        XCTAssertEqual(PFHealthspanFormat.ageVerdict(PFYearsRange(low: -1.6, high: 2.2, mid: nil)).direction, .aboutRight)
    }

    func testNarrowYoungerRangeIsWidenedToTwoWholeYears() {
        XCTAssertEqual(PFHealthspanFormat.ageVerdict(PFYearsRange(low: -4.1, high: -3.9, mid: nil)).text, "3 to 5 years younger")
    }

    func testPaceTextUsesATrueMinusAndAnX() {
        XCTAssertEqual(PFHealthspanFormat.paceText(-0.57), "\u{2212}0.6x")
    }

    func testPaceTextOfNothingHasNoSign() {
        XCTAssertEqual(PFHealthspanFormat.paceText(-0.02), "0.0x")
    }

    func testPaceRangeTextOrdersLowToHigh() {
        XCTAssertEqual(PFHealthspanFormat.paceRangeText(low: 2.2, high: -1.0), "\u{2212}1.0x to 2.2x")
    }

    func testPaceFractionPutsTheLeftEdgeAtZero() {
        XCTAssertEqual(PFHealthspanFormat.paceFraction(-1), 0, accuracy: 0.0001)
    }

    func testPaceFractionPutsOnePointZeroAtHalf() {
        XCTAssertEqual(PFHealthspanFormat.paceFraction(1), 0.5, accuracy: 0.0001)
    }

    func testPaceFractionIsClampedOnTheRight() {
        XCTAssertEqual(PFHealthspanFormat.paceFraction(4.2), 1, accuracy: 0.0001)
    }

    func testPaceBelowNineTenthsIsSlower() {
        XCTAssertEqual(PFHealthspanFormat.paceChip(0.4), .slower)
    }

    func testPaceNearOneIsSteady() {
        XCTAssertEqual(PFHealthspanFormat.paceChip(1.05), .steady)
    }

    func testPaceAboveOnePointOneIsFaster() {
        XCTAssertEqual(PFHealthspanFormat.paceChip(1.6), .faster)
    }

    func testNextUpdateOnAWednesdayIsFiveDays() {
        // 2030-03-13 is a Wednesday; the next ISO week starts on Monday the 18th.
        XCTAssertEqual(PFHealthspanFormat.daysToNextUpdate(asOf: "2030-03-13"), 5)
    }

    func testNextUpdateOnAMondayIsSevenDays() {
        XCTAssertEqual(PFHealthspanFormat.daysToNextUpdate(asOf: "2030-03-11"), 7)
    }

    func testNextUpdateOnASundayIsTomorrow() {
        XCTAssertEqual(PFHealthspanFormat.nextUpdateText(asOf: "2030-03-17"), "NEXT UPDATE TOMORROW")
    }

    func testNextUpdateTextNamesTheDays() {
        XCTAssertEqual(PFHealthspanFormat.nextUpdateText(asOf: "2030-03-13"), "NEXT UPDATE IN 5 DAYS")
    }

    func testNextUpdateWithABadDateIsNil() {
        XCTAssertNil(PFHealthspanFormat.nextUpdateText(asOf: "soon"))
    }

    func testYearsTextCarriesItsSign() {
        XCTAssertEqual(PFHealthspanFormat.yearsText(0.83), "+0.8")
    }

    func testYearsRangeTextOrdersLowToHigh() {
        XCTAssertEqual(PFHealthspanFormat.yearsRangeText(low: -2.4, high: -4.7), "\u{2212}4.7 to \u{2212}2.4")
    }

    // MARK: Week keys

    func testIsoWeekKeyGivesItsMonday() {
        XCTAssertEqual(PFDocDate.monday(ofWeek: "2026-W42"), "2026-10-12")
    }

    func testIsoWeekRangeTextRunsMondayToSunday() {
        XCTAssertEqual(PFDocDate.weekRangeText("2026-W42"), "OCT 12 - OCT 18")
    }

    func testIsoWeekRangeAcrossAMonthChange() {
        XCTAssertEqual(PFDocDate.weekRangeText("2026-W40"), "SEP 28 - OCT 4")
    }

    func testBadWeekKeyHasNoRange() {
        XCTAssertNil(PFDocDate.weekRangeText("last week"))
    }

    func testDayMonthYearText() {
        XCTAssertEqual(PFDocDate.dayMonthYear("2026-06-01"), "1 Jun 2026")
    }

    // MARK: Driver bar

    func testBarScaleIsAtLeastOneYear() {
        XCTAssertEqual(PFDriverBar.scale([PFPaceMetric(key: "a", label: "A", years6m: 0.2, years30d: -0.1)]), 1)
    }

    func testBarScaleFollowsTheLargestImpactInEitherWindow() {
        let metrics = [PFPaceMetric(key: "a", label: "A", years6m: -3.5, years30d: 0.1),
                       PFPaceMetric(key: "b", label: "B", years6m: 0.2, years30d: 4.2)]
        XCTAssertEqual(PFDriverBar.scale(metrics), 4.2, accuracy: 0.0001)
    }

    func testNoImpactSitsInTheMiddleOfTheBar() {
        XCTAssertEqual(PFDriverBar.position(years: 0, scale: 2), 0.5, accuracy: 0.0001)
    }

    func testTakingYearsOffMovesTheMarkerRight() {
        XCTAssertGreaterThan(PFDriverBar.position(years: -1, scale: 2), 0.5)
    }

    func testAddingYearsMovesTheMarkerLeft() {
        XCTAssertLessThan(PFDriverBar.position(years: 1, scale: 2), 0.5)
    }

    func testMarkerIsClampedToTheBar() {
        XCTAssertEqual(PFDriverBar.position(years: -9, scale: 2), 1, accuracy: 0.0001)
    }

    func testBarFillsSegmentsUpToTheSixMonthMarker() {
        XCTAssertEqual(PFDriverBar.make(years6m: -2, years30d: nil, scale: 2).filled, 10)
    }

    func testBarWithoutASixMonthFigureFillsNothing() {
        XCTAssertEqual(PFDriverBar.make(years6m: nil, years30d: -1, scale: 2).filled, 0)
    }

    func testBarHalfFilledAtNoImpact() {
        XCTAssertEqual(PFDriverBar.make(years6m: 0, years30d: 0, scale: 2).filled, 5)
    }

    func testBarCarriesBothMarkers() {
        let bar = PFDriverBar.make(years6m: -1, years30d: 1, scale: 2)
        XCTAssertEqual([bar.marker6m ?? -1, bar.marker30d ?? -1], [0.75, 0.25])
    }

    func testDriverBarReadsTheThirtyDayFigureFromThePaceBlock() throws {
        let h = try XCTUnwrap(healthspan())
        let sleep = try XCTUnwrap(h.drivers.first { $0.key == "sleep_duration" })
        let bar = PFDriverBar.make(driver: sleep, pace: h.pace, scale: 4)
        XCTAssertEqual(bar.marker30d ?? -1, PFDriverBar.position(years: 0.9, scale: 4), accuracy: 0.0001)
    }

    func testDriverGroupsSeparateSleepActivityAndBody() {
        XCTAssertEqual(["sleep_consistency", "zones_4_5", "lean_mass"].map { PFDriverGroup.of($0) }, [.sleep, .activity, .body])
    }

    // MARK: Healthspan weeks on the phone

    private func week(_ key: String, low: Double = 35, high: Double = 38) -> PFHealthspanWeek {
        PFHealthspanWeek(week: key, asOf: "2030-03-13", ageLow: low, ageHigh: high, paceValue: 0.2, paceLow: -0.5, paceHigh: 1.1)
    }

    func testWeekEntryComesFromTheDocument() throws {
        let h = try XCTUnwrap(healthspan())
        XCTAssertEqual(PFHealthspanHistory.entry(from: h)?.week, "2030-W11")
    }

    func testWeekEntryNeedsAWeekKey() throws {
        var h = try XCTUnwrap(healthspan())
        h.pace?.week = nil
        XCTAssertNil(PFHealthspanHistory.entry(from: h))
    }

    func testUpsertAddsANewWeekInOrder() {
        let out = PFHealthspanHistory.upserting(week("2030-W10"), into: [week("2030-W11")])
        XCTAssertEqual(out.map(\.week), ["2030-W10", "2030-W11"])
    }

    func testUpsertReplacesTheSameWeek() {
        let out = PFHealthspanHistory.upserting(week("2030-W11", low: 30, high: 33), into: [week("2030-W11")])
        XCTAssertEqual(out.map(\.ageLow), [30])
    }

    func testHistoryIsCappedAtTheNewestWeeks() {
        var weeks: [PFHealthspanWeek] = []
        for n in 1...(PFHealthspanHistory.maxWeeks + 5) {
            weeks = PFHealthspanHistory.upserting(week(String(format: "2030-W%03d", n)), into: weeks)
        }
        XCTAssertEqual(weeks.count, PFHealthspanHistory.maxWeeks)
    }

    func testHistoryRoundTripsThroughItsEncoding() {
        let weeks = [week("2030-W10"), week("2030-W11")]
        XCTAssertEqual(PFHealthspanHistory.decode(PFHealthspanHistory.encode(weeks)), weeks)
    }

    func testHistoryDecodesGarbageAsNothing() {
        XCTAssertEqual(PFHealthspanHistory.decode(Data("not json".utf8)), [])
    }

    func testHistoryDecodesNoDataAsNothing() {
        XCTAssertEqual(PFHealthspanHistory.decode(nil), [])
    }

    func testStepperGoesBackOneStoredWeek() {
        XCTAssertEqual(PFHealthspanHistory.neighbour(of: "2030-W11", step: -1, in: [week("2030-W10"), week("2030-W11")]), "2030-W10")
    }

    func testStepperStopsAtTheNewestWeek() {
        XCTAssertNil(PFHealthspanHistory.neighbour(of: "2030-W11", step: 1, in: [week("2030-W10"), week("2030-W11")]))
    }

    // MARK: Journal impact

    private let journalMetric = """
    {"as_of": "2030-03-13", "window_days": 90, "min_each": 5,
     "outcome": {"key": "charge", "label": "Charge (NOOP)", "source": "NOOP", "unit": "%", "days": 90},
     "hurts": [{"id": "late_meal", "label": "A meal after 21:00", "group": "nutrition", "n_with": 12, "n_without": 70, "mean_with": 52.0,
                "mean_without": 61.0, "diff": -9.0, "pct": -14.8, "t": -2.6, "clear": true, "strong": true, "confidence": "medium",
                "note": "Synthetic note.", "action": {"id": "late_meal_action", "text": "Eat earlier.", "why": "Synthetic.", "effort": {"value": 0, "unit": "min", "label": "no extra time"}}},
               {"id": "alcohol", "label": "Alcohol", "n_with": 9, "n_without": 80, "pct": -6.2, "clear": true, "strong": false}],
     "helps": [{"id": "easy_day", "label": "An easy day", "n_with": 30, "n_without": 60, "pct": 9.1, "clear": true, "strong": true},
               {"id": "walk", "label": "A long walk", "n_with": 20, "n_without": 70, "pct": 3.4, "clear": true, "strong": false}],
     "no_clear_effect": [{"id": "short_sleep", "label": "A night under 7 hours", "n_with": 66, "n_without": 22, "pct": -2.1, "clear": false}],
     "not_enough_data": [{"id": "late_session", "label": "A session after 20:00", "group": "training", "n_with": 1, "n_without": 89},
                         {"id": "travel_day", "label": "A travel day", "n_with": 0, "n_without": 3}],
     "tested": 5}
    """

    private func impact() -> PFJournalImpact? {
        PFIntelDocsParse.state(wrap("journal_impact", metric: journalMetric), id: PFDocID.journalImpact, PFIntelDocsParse.journalImpact).value
    }

    func testImpactKeepsTheFourLists() throws {
        let j = try XCTUnwrap(impact())
        XCTAssertEqual([j.hurts.count, j.helps.count, j.noClearEffect.count, j.notEnoughData.count], [2, 2, 1, 2])
    }

    func testImpactNamesTheOutcomeAndItsSource() throws {
        let j = try XCTUnwrap(impact())
        XCTAssertEqual([j.outcomeLabel ?? "", j.outcomeSource ?? ""], ["Charge (NOOP)", "NOOP"])
    }

    func testImpactEntryKeepsItsDaysAndPercent() throws {
        let entry = try XCTUnwrap(impact()?.hurts.first)
        XCTAssertEqual([Double(entry.nWith), Double(entry.nWithout), entry.pct ?? 0], [12, 70, -14.8])
    }

    func testStrongImpactCarriesItsAction() throws {
        XCTAssertEqual(impact()?.hurts.first?.action?.text, "Eat earlier.")
    }

    func testImpactWithAllListsEmptyIsNotUsable() {
        let state = PFIntelDocsParse.state(wrap("journal_impact", metric: "{\"hurts\": [], \"helps\": []}"), id: PFDocID.journalImpact,
                                           PFIntelDocsParse.journalImpact)
        XCTAssertNil(state.value)
    }

    func testImpactMinimumDaysDefaultsToFive() {
        let state = PFIntelDocsParse.state(wrap("journal_impact", metric: "{\"hurts\": [{\"id\": \"a\", \"label\": \"A\", \"pct\": -5}]}"),
                                           id: PFDocID.journalImpact, PFIntelDocsParse.journalImpact)
        XCTAssertEqual(state.value?.minEach, 5)
    }

    func testImpactPercentUsesATrueMinus() {
        XCTAssertEqual(PFImpactFormat.pctText(-14.8), "\u{2212}15 %")
    }

    func testImpactPercentOfAPositiveEffectHasAPlus() {
        XCTAssertEqual(PFImpactFormat.pctText(9.1), "+9 %")
    }

    func testImpactPercentOfNothingIsZero() {
        XCTAssertEqual(PFImpactFormat.pctText(0.3), "0 %")
    }

    func testBarScaleIsAtLeastTenPercent() throws {
        let j = try XCTUnwrap(impact())
        XCTAssertEqual(PFImpactFormat.barScale(j.noClearEffect), 10)
    }

    func testBarScaleFollowsTheLargestEffect() throws {
        let j = try XCTUnwrap(impact())
        XCTAssertEqual(PFImpactFormat.barScale(j.scored), 14.8, accuracy: 0.0001)
    }

    func testBarFractionIsASignlessShareOfTheScale() {
        XCTAssertEqual(PFImpactFormat.barFraction(-7.4, scale: 14.8), 0.5, accuracy: 0.0001)
    }

    func testBarFractionIsClamped() {
        XCTAssertEqual(PFImpactFormat.barFraction(40, scale: 14.8), 1, accuracy: 0.0001)
    }

    func testHurtsAreSortedWorstFirst() throws {
        let j = try XCTUnwrap(impact())
        XCTAssertEqual(PFImpactFormat.sortedHurts(j.hurts.reversed()).map(\.id), ["late_meal", "alcohol"])
    }

    func testHelpsAreSortedBestFirst() throws {
        let j = try XCTUnwrap(impact())
        XCTAssertEqual(PFImpactFormat.sortedHelps(j.helps.reversed()).map(\.id), ["easy_day", "walk"])
    }

    func testNeedTextNamesBothSidesWhenBothAreShort() {
        let item = PFNotEnough(id: "a", label: "A", group: nil, nWith: 1, nWithout: 2)
        XCTAssertEqual(PFImpactFormat.needText(item, minEach: 5), "Needs 4 more days with it and 3 more days without.")
    }

    func testNeedTextNamesOnlyTheShortSide() {
        let item = PFNotEnough(id: "a", label: "A", group: nil, nWith: 4, nWithout: 89)
        XCTAssertEqual(PFImpactFormat.needText(item, minEach: 5), "Needs 1 more day with it.")
    }

    func testNeedTextForTheDaysWithoutIt() {
        let item = PFNotEnough(id: "a", label: "A", group: nil, nWith: 40, nWithout: 3)
        XCTAssertEqual(PFImpactFormat.needText(item, minEach: 5), "Needs 2 more days without it.")
    }

    func testCountsTextIsPlural() {
        XCTAssertEqual(PFImpactFormat.countsText(with: 66, without: 22), "66 days with it, 22 without")
    }

    func testFirstVisitMarksNothingNew() {
        XCTAssertEqual(PFSeenIDs.newIDs(current: ["a", "b"], seen: nil), [])
    }

    func testLaterVisitMarksOnlyUnseenIdsNew() {
        XCTAssertEqual(PFSeenIDs.newIDs(current: ["a", "b", "c"], seen: ["a", "b"]), ["c"])
    }

    func testSeenIdsRoundTrip() {
        XCTAssertEqual(PFSeenIDs.decode(PFSeenIDs.encode(["b", "a"])), ["a", "b"])
    }

    func testSeenIdsNeverForgetOldOnes() {
        XCTAssertEqual(PFSeenIDs.updated(seen: ["a"], current: ["b"]), ["a", "b"])
    }

    // MARK: Highlights

    private let highlightsMetric = """
    {"as_of": "2030-03-13", "noop_since": "2030-02-01", "garmin_since": "2029-01-01",
     "records": [
       {"id": "rest", "label": "Rest", "periods": [
         {"id": "1M", "label": "Last 30 days", "noop": {"value": 83.1, "display": "Rest 83 %", "date": "2030-03-11", "days_ago": 2, "source": "NOOP", "label": "Rest (NOOP)"},
          "garmin": {"value": 82.0, "display": "Sleep score 82", "date": "2030-03-11", "days_ago": 2, "source": "Garmin", "label": "Sleep score (Garmin)"}},
         {"id": "all", "label": "All time", "noop": null, "garmin": {"value": 90.0, "display": "Sleep score 90", "date": "2029-06-01", "days_ago": 285, "source": "Garmin"}}]},
       {"id": "effort", "label": "Effort", "periods": [{"id": "1M", "label": "Last 30 days", "noop": {"value": 70.8, "display": "Effort 14.9 of 21", "date": "2030-03-12", "days_ago": 1, "source": "NOOP"}}]}],
     "streaks": [
       {"id": "rest_70", "label": "Rest 70 % or more", "source": "NOOP", "unit": "days", "rule": "r", "current": 6, "best": 9, "since": "2030-03-08", "alive": true, "line": "Synthetic line."},
       {"id": "charge_green", "label": "Green Charge", "source": "NOOP", "unit": "days", "current": 9, "best": 9, "alive": true},
       {"id": "effort_10", "label": "Effort 10 or more", "source": "NOOP", "unit": "days", "current": 0, "best": 4, "alive": false},
       {"id": "plan_weeks", "label": "Weeks with 80 % done", "source": "PaceForge", "unit": "weeks", "current": 12, "best": 12, "alive": true}],
     "notable": [
       {"id": "rhr_low", "label": "Lowest resting heart rate", "value": 39.0, "display": "39 bpm", "date": "2029-06-01", "days_ago": 285, "source": "Garmin", "scope": "since 2029-01-01"},
       {"id": "sleep_longest", "label": "Longest sleep", "value": 9.0, "display": "8 h 59", "date": "2030-03-01", "days_ago": 12, "source": "Garmin"},
       {"id": "max_hr", "label": "Maximum heart rate", "value": 197.0, "display": "197 bpm", "date": "2030-03-07", "days_ago": 6, "source": "Garmin", "detail": "indoor cardio"}]}
    """

    private func highlights() -> PFHighlights? {
        PFIntelDocsParse.state(wrap("highlights", metric: highlightsMetric), id: PFDocID.highlights, PFIntelDocsParse.highlights).value
    }

    func testHighlightsKeepRecordsStreaksAndNotableStats() throws {
        let h = try XCTUnwrap(highlights())
        XCTAssertEqual([h.records.count, h.streaks.count, h.notable.count], [2, 4, 3])
    }

    func testRecordPeriodKeepsTheStrapRecordAndTheGarminRecordApart() throws {
        let period = try XCTUnwrap(highlights()?.record("rest")?.period("1M"))
        XCTAssertEqual([period.noop?.source ?? "", period.garmin?.source ?? ""], ["NOOP", "Garmin"])
    }

    func testRecordPeriodWithNoStrapValueHasNone() throws {
        let period = try XCTUnwrap(highlights()?.record("rest")?.period("all"))
        XCTAssertNil(period.noop)
    }

    func testStreakCountTextIsSingularForOneDay() {
        let s = PFStreak(id: "a", label: "A", source: nil, unit: "days", rule: nil, current: 1, best: 1, since: nil, alive: true, line: nil)
        XCTAssertEqual(s.countText, "1 Day")
    }

    func testStreakCountTextInWeeks() throws {
        let weeks = try XCTUnwrap(highlights()?.streaks.last)
        XCTAssertEqual(weeks.countText, "12 Weeks")
    }

    func testStreakBestText() throws {
        let broken = try XCTUnwrap(highlights()?.streaks.first { $0.id == "effort_10" })
        XCTAssertEqual(broken.bestText, "Best 4 days")
    }

    func testLeadStreakIsTheLongestAliveStreakInDays() throws {
        let h = try XCTUnwrap(highlights())
        XCTAssertEqual(PFHighlightsLogic.leadStreak(h.streaks)?.id, "charge_green")
    }

    func testLeadStreakIgnoresAWeeksStreakEvenWhenItIsLonger() throws {
        let h = try XCTUnwrap(highlights())
        XCTAssertNotEqual(PFHighlightsLogic.leadStreak(h.streaks)?.id, "plan_weeks")
    }

    func testLeadStreakTieGoesToTheFirstListed() {
        let a = PFStreak(id: "a", label: "A", source: nil, unit: "days", rule: nil, current: 5, best: 5, since: nil, alive: true, line: nil)
        let b = PFStreak(id: "b", label: "B", source: nil, unit: "days", rule: nil, current: 5, best: 5, since: nil, alive: true, line: nil)
        XCTAssertEqual(PFHighlightsLogic.leadStreak([a, b])?.id, "a")
    }

    func testNoAliveStreakMeansNoLead() {
        let a = PFStreak(id: "a", label: "A", source: nil, unit: "days", rule: nil, current: 0, best: 5, since: nil, alive: false, line: nil)
        XCTAssertNil(PFHighlightsLogic.leadStreak([a]))
    }

    func testStreakChipCarriesTheCount() throws {
        XCTAssertEqual(PFHighlightsLogic.chip(highlights())?.text, "9")
    }

    func testStreakChipIsSpokenWithItsLabel() throws {
        XCTAssertEqual(PFHighlightsLogic.chip(highlights())?.spoken, "9 day streak: Green Charge")
    }

    func testNoHighlightsMeansNoChip() {
        XCTAssertNil(PFHighlightsLogic.chip(nil))
    }

    func testRecordDialFractionIsTheStrapValueOnItsHundredAxis() throws {
        let rest = try XCTUnwrap(highlights()?.record("rest"))
        XCTAssertEqual(PFHighlightsLogic.dialFraction(rest, period: .month) ?? -1, 0.831, accuracy: 0.0001)
    }

    func testRecordDialHasNoFractionWithoutAStrapValue() throws {
        let rest = try XCTUnwrap(highlights()?.record("rest"))
        XCTAssertNil(PFHighlightsLogic.dialFraction(rest, period: .allTime))
    }

    func testHighlightPeriodTitles() {
        XCTAssertEqual(PFHighlightPeriod.allCases.map(\.title), ["1M", "3M", "ALL TIME"])
    }

    func testValuePartsSplitANumberAndItsUnit() {
        XCTAssertEqual(PFHighlightsLogic.valueParts("39 bpm").unit, "bpm")
    }

    func testValuePartsReadAHoursAndMinutesSleep() {
        XCTAssertEqual(PFHighlightsLogic.valueParts("8 h 59").number, "8:59")
    }

    func testValuePartsOfABareNumberHaveNoUnit() {
        XCTAssertEqual(PFHighlightsLogic.valueParts("1185").unit, "")
    }

    func testValuePartsOfNothing() {
        XCTAssertEqual(PFHighlightsLogic.valueParts("").number, "")
    }

    func testDateCaptionNamesTheDayAndHowLongAgo() {
        XCTAssertEqual(PFHighlightsLogic.dateCaption(date: "2029-06-01", daysAgo: 285), "1 Jun 2029 \u{00B7} 285 days ago")
    }

    func testDateCaptionOfYesterday() {
        XCTAssertEqual(PFHighlightsLogic.dateCaption(date: "2030-03-12", daysAgo: 1), "12 Mar 2030 \u{00B7} yesterday")
    }

    func testDateCaptionWithoutADateIsNil() {
        XCTAssertNil(PFHighlightsLogic.dateCaption(date: nil, daysAgo: 3))
    }

    func testNotableSymbolFallsBackToAStar() {
        XCTAssertEqual(PFHighlightsLogic.notableSymbol("something_new"), "star")
    }

    func testHighlightsWithNothingInThemAreNotUsable() {
        let state = PFIntelDocsParse.state(wrap("highlights", metric: "{\"as_of\": \"2030-03-13\"}"), id: PFDocID.highlights, PFIntelDocsParse.highlights)
        XCTAssertNil(state.value)
    }

    // MARK: Monthly report

    private let monthlyMetric = """
    {"as_of": "2030-03-13",
     "periods": [
       {"id": "last_full", "label": "February 2030", "from": "2030-02-01", "to": "2030-02-28", "days": 28, "compared_with": "January 2030",
        "metrics": [
          {"key": "charge", "label": "Charge", "unit": "%", "source": "NOOP", "state": "ok", "current": {"value": 61.2, "n": 28}, "previous": {"value": 70.4, "n": 31},
           "delta": -9.2, "pct": -13.1, "direction": "down", "assessment": "worse", "series_label": "Charge (NOOP)"},
          {"key": "effort", "label": "Effort", "unit": "of 21", "source": "NOOP", "state": "ok", "current": {"value": 12.3, "n": 28}, "previous": {"value": 12.1, "n": 31},
           "delta": 0.2, "pct": 1.6, "direction": "flat", "assessment": null},
          {"key": "weight", "label": "Weight", "unit": "kg", "source": "Garmin", "state": "not enough data", "current": null, "previous": null, "delta": null,
           "reason": "0 readings this month; 2 are needed"}],
        "movers": [{"key": "charge", "label": "Charge (NOOP)", "unit": "", "source": "NOOP", "previous": 70.4, "current": 61.2, "delta": -9.2, "pct": -13.1,
                    "assessment": "worse", "what_moved": [{"behaviour": "late_session", "label": "A late session", "lag_days": 1, "strength": "moderate", "sentence": "Synthetic link sentence."}],
                    "action": {"id": "mover_action", "text": "Sleep earlier.", "why": "Synthetic."}}]},
       {"id": "month_to_date", "label": "March 2030 so far", "days": 13, "compared_with": "February 2030", "metrics": [], "movers": []}],
     "goals": {"weight": {"target_kg": 87.0, "kg_to_go": 3.9, "text": "Synthetic weight sentence.", "status": "behind", "source": "Garmin"},
               "race": {"name": "Synthetic 10 km", "days_to": 28, "text": "Synthetic race sentence.", "status": "on track", "source": "Garmin"}},
     "focus": [{"text": "Fix the wake time.", "why": "Synthetic why.", "effort": "no extra time", "topic": "sleep", "from": "next_best_action"},
               {"text": "Add one easy run.", "why": "Synthetic.", "effort": {"value": 30, "unit": "min/week", "label": "30 min/week"}, "topic": "zones"}]}
    """

    private func monthly() -> PFMonthlyReport? {
        PFIntelDocsParse.state(wrap("monthly_report", metric: monthlyMetric), id: PFDocID.monthlyReport, PFIntelDocsParse.monthlyReport).value
    }

    func testMonthlyReportKeepsBothPeriodsInOrder() throws {
        let m = try XCTUnwrap(monthly())
        XCTAssertEqual(m.periods.map(\.id), ["last_full", "month_to_date"])
    }

    func testMonthlyPeriodNamesWhatItIsComparedWith() throws {
        XCTAssertEqual(monthly()?.period("last_full")?.comparedWith, "January 2030")
    }

    func testMonthlyRowWithoutDataKeepsTheServersReason() throws {
        let weight = try XCTUnwrap(monthly()?.period("last_full")?.rows.last)
        XCTAssertEqual(weight.reason, "0 readings this month; 2 are needed")
    }

    func testMonthlyRowWithoutDataHasNoData() throws {
        let weight = try XCTUnwrap(monthly()?.period("last_full")?.rows.last)
        XCTAssertFalse(weight.hasData)
    }

    func testMonthlyMoverKeepsWhatMovedItAndItsAction() throws {
        let mover = try XCTUnwrap(monthly()?.period("last_full")?.movers.first)
        XCTAssertEqual([mover.whatMoved.first?.sentence ?? "", mover.action?.text ?? ""], ["Synthetic link sentence.", "Sleep earlier."])
    }

    func testMonthlyGoalsCarryTheServersSentences() throws {
        let goals = try XCTUnwrap(monthly()?.goals)
        XCTAssertEqual(goals.map { $0.text ?? "" }, ["Synthetic weight sentence.", "Synthetic race sentence."])
    }

    func testMonthlyWeightGoalHeadlineNamesTheTargetAndWhatIsLeft() throws {
        XCTAssertEqual(monthly()?.goals.first?.headline, "87 kg \u{00B7} 3.9 kg to go")
    }

    func testMonthlyFocusReadsEffortAsASentenceOrAnObject() throws {
        let focus = try XCTUnwrap(monthly()?.focus)
        XCTAssertEqual(focus.map { $0.effortText ?? "" }, ["no extra time", "30 min/week"])
    }

    func testMonthlyValueTextWholePercentForScores() throws {
        let charge = try XCTUnwrap(monthly()?.period("last_full")?.rows.first)
        XCTAssertEqual(PFMonthlyFormat.valueText(charge, 61.2), "61 %")
    }

    func testMonthlyValueTextOneDecimalForEffort() throws {
        let effort = try XCTUnwrap(monthly()?.period("last_full")?.rows[1])
        XCTAssertEqual(PFMonthlyFormat.valueText(effort, 12.3), "12.3 of 21")
    }

    func testMonthlyDeltaTextNamesTheMonthBefore() throws {
        let charge = try XCTUnwrap(monthly()?.period("last_full")?.rows.first)
        XCTAssertEqual(PFMonthlyFormat.deltaText(charge, comparedWith: "January 2030"), "\u{2212}9.2 on January 2030")
    }

    func testMonthlyWorseRowHasADownTriangleInTheWorseTone() throws {
        let charge = try XCTUnwrap(monthly()?.period("last_full")?.rows.first)
        XCTAssertEqual(charge.mark?.pointsUp, false)
    }

    func testMonthlyWorseRowIsToneBad() throws {
        let charge = try XCTUnwrap(monthly()?.period("last_full")?.rows.first)
        XCTAssertEqual(charge.mark?.tone, .bad)
    }

    func testMonthlyFlatRowHasNoTriangle() throws {
        let effort = try XCTUnwrap(monthly()?.period("last_full")?.rows[1])
        XCTAssertNil(effort.mark)
    }

    func testMonthlyChipTexts() throws {
        let rows = try XCTUnwrap(monthly()?.period("last_full")?.rows)
        XCTAssertEqual(rows.map { PFMonthlyFormat.chipText($0) ?? "-" }, ["WORSE", "STEADY", "-"])
    }

    func testMonthlyReportWithoutPeriodsIsNotUsable() {
        let state = PFIntelDocsParse.state(wrap("monthly_report", metric: "{\"as_of\": \"2030-03-13\", \"periods\": []}"),
                                           id: PFDocID.monthlyReport, PFIntelDocsParse.monthlyReport)
        XCTAssertNil(state.value)
    }

    // MARK: My plan

    private let planMetric = """
    {"as_of": "2030-03-13", "week": {"from": "2030-03-11", "to": "2030-03-17", "iso": "2030-W11"}, "plan": {"name": "Synthetic plan", "phase": "Build"},
     "planned_sessions": 8, "done": 5, "partial": 1, "missed": 0, "pct_accomplished": 62, "days_left": 5,
     "next_item": {"label": "Synthetic class", "date": "2030-03-14", "weekday": "Thu", "minutes": 45, "hard": false, "sport": "other"},
     "items": [{"label": "Synthetic intervals", "done": true, "date": "2030-03-11", "weekday": "Mon", "status": "done", "minutes": 30, "hard": true, "sport": "run"},
               {"label": "Synthetic easy run", "done": true, "date": "2030-03-12", "weekday": "Tue", "status": "partial", "minutes": 35, "hard": false, "sport": "run"},
               {"label": "Synthetic class", "done": false, "date": "2030-03-14", "weekday": "Thu", "status": "upcoming", "minutes": 45, "hard": false, "sport": "other"}],
     "extras": []}
    """

    private func plan() -> PFMyPlan? {
        PFIntelDocsParse.state(wrap("my_plan", metric: planMetric), id: PFDocID.myPlan, PFIntelDocsParse.myPlan).value
    }

    func testPlanKeepsItsCounts() throws {
        let p = try XCTUnwrap(plan())
        XCTAssertEqual([p.planned, p.done, p.partial, p.missed], [8, 5, 1, 0])
    }

    func testPlanHeaderNamesTheDaysLeftAndThePercent() throws {
        XCTAssertEqual(plan()?.headerText, "5 DAYS LEFT \u{00B7} 62 % ACCOMPLISHED")
    }

    func testPlanHeaderForTheLastDay() throws {
        var p = try XCTUnwrap(plan())
        p.daysLeft = 1
        XCTAssertEqual(p.headerText, "1 DAY LEFT \u{00B7} 62 % ACCOMPLISHED")
    }

    func testPlanHeaderForACompleteWeek() throws {
        var p = try XCTUnwrap(plan())
        p.daysLeft = 0
        XCTAssertEqual(p.headerText, "WEEK COMPLETE \u{00B7} 62 % ACCOMPLISHED")
    }

    func testPlanHeaderWithoutAPercentKeepsTheDaysLeft() throws {
        var p = try XCTUnwrap(plan())
        p.pctAccomplished = nil
        XCTAssertEqual(p.headerText, "5 DAYS LEFT")
    }

    func testPlanProgressIsThePercentAsAFraction() throws {
        XCTAssertEqual(plan()?.progress ?? -1, 0.62, accuracy: 0.0001)
    }

    func testPlanProgressFallsBackToDoneOverPlanned() throws {
        var p = try XCTUnwrap(plan())
        p.pctAccomplished = nil
        XCTAssertEqual(p.progress, 0.625, accuracy: 0.0001)
    }

    func testPlanProgressIsClamped() throws {
        var p = try XCTUnwrap(plan())
        p.pctAccomplished = 140
        XCTAssertEqual(p.progress, 1, accuracy: 0.0001)
    }

    func testPlanItemsKeepTheirStatus() throws {
        let p = try XCTUnwrap(plan())
        XCTAssertEqual(p.items.map(\.status), ["done", "partial", "upcoming"])
    }

    func testPlanItemDetailTextNamesTheDayAndLength() throws {
        let p = try XCTUnwrap(plan())
        XCTAssertEqual(p.items.first?.detailText, "Mon \u{00B7} 30 min \u{00B7} hard")
    }

    func testPlanNextItemDetailText() throws {
        XCTAssertEqual(plan()?.next?.detailText, "Thu \u{00B7} 45 min")
    }

    func testPlanWithoutPlannedSessionsOrItemsIsNotUsable() {
        let state = PFIntelDocsParse.state(wrap("my_plan", metric: "{\"planned_sessions\": 0, \"items\": []}"), id: PFDocID.myPlan, PFIntelDocsParse.myPlan)
        XCTAssertNil(state.value)
    }

    func testPlanWithoutACountIsNotUsable() {
        let state = PFIntelDocsParse.state(wrap("my_plan", metric: "{\"as_of\": \"2030-03-13\"}"), id: PFDocID.myPlan, PFIntelDocsParse.myPlan)
        XCTAssertNil(state.value)
    }

    func testPlanItemWithoutAStatusReadsFromItsDoneFlag() {
        let state = PFIntelDocsParse.state(
            wrap("my_plan", metric: "{\"planned_sessions\": 1, \"items\": [{\"label\": \"A\", \"done\": true}]}"),
            id: PFDocID.myPlan, PFIntelDocsParse.myPlan)
        XCTAssertEqual(state.value?.items.first?.status, "done")
    }
}
