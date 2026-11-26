import XCTest

/// Build 530, APP-3: the journal. The morning sheet (5b), the evening reflection (5d), the behaviour insights (5e) and Customise (5f), each
/// opened with `-Plan529Open` over the Plan tab. They run on `--demo-seed` data and the synthetic fixtures (`Fixtures529/zzz-530-journal.json`
/// serves `data/journal-view.json`; the fixture day is 2030-03-13, so the morning sheet is about 2030-03-12). Answers are saved through the
/// journal's own store and read back from it. `-Journal530SeedPrevious` writes the day before's answers for "Same as yesterday". The lock
/// screen action (5c) is a notification and has no simulator test. Screenshot names start with the screen code.
final class Journal530UITests: XCTestCase {
    private let screenKey = "Did you view a screen in bed?"
    private let thirdKey = "Did you share your bed?"
    private let secondKey = "Did you eat close to bedtime?"
    private let alcoholKey = "Did you drink any alcohol?"

    private func launch(open target: String, extra: [String] = []) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--demo-seed", "-theme.appearance", "dark", "-PaceForgeFixture", "-Plan529Open", target])
        app.launchArguments.append(contentsOf: extra)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                "The synthetic fixture should be bundled with the UI tests.")
        app.launchEnvironment["PF_FIXTURE_JSON"] = try Fixtures529.merged(Data(contentsOf: url))
        app.launch()
        dumpHierarchyOnFailure(app)
        app.openTab("Plan")
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func count(_ app: XCUIApplication, prefix: String) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).count
    }

    /// Swipes the sheet up until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        return element.exists && element.isHittable
    }

    // MARK: 5b Morning

    func testMorningSheetShowsTheDeviceAnswersWithEvidenceThenFiveQuestions() throws {
        let app = try launch(open: "journal-morning")
        XCTAssertTrue(app.element("pf530-journal-morning").waitForExistence(timeout: 30), "The morning sheet should open over the Plan tab.")
        XCTAssertTrue(app.element("pf530-journal-auto").waitForExistence(timeout: 20), "The device-answered block should show.")
        for id in ["hard_day", "late_session", "bedtime_late", "short_sleep"] {
            XCTAssertTrue(app.element("pf530-journal-auto-row-\(id)").exists, "\(id) should be a row.")
        }
        XCTAssertTrue(app.element("pf530-journal-auto-row-hard_day").label.contains("Doubles race, 66 min"), "A row should carry its evidence.")
        XCTAssertFalse(app.element("pf530-journal-auto-row-strength_day").exists, "A No answer is in the line under the block, not a row.")
        XCTAssertTrue(app.element("pf530-journal-auto-note").label.contains("A strength day"), "The No answers should be named under the block.")
        XCTAssertEqual(count(app, prefix: "pf530-journal-row-"), 5, "The morning asks five questions.")
        attach(app, "5b morning sheet")
    }

    func testTappingYesAndSavingWritesTheAnswerToTheJournal() throws {
        let app = try launch(open: "journal-morning")
        let yes = app.element("pf530-journal-yes-\(thirdKey)")
        XCTAssertTrue(yes.waitForExistence(timeout: 30), "The first question should have a Yes.")
        XCTAssertTrue(reveal(yes, in: app), "Yes should be reachable.")
        yes.tap()
        XCTAssertTrue(yes.isSelected, "A tap should choose Yes on screen.")
        XCTAssertTrue(app.element("pf530-journal-answered").label.contains("0 of 5"), "Nothing is in the journal before Save.")
        let save = app.element("pf530-journal-save")
        XCTAssertTrue(reveal(save, in: app), "A changed answer should offer Save.")
        save.tap()
        XCTAssertTrue(app.element("pf530-journal-saved").waitForExistence(timeout: 20), "Saving should say it saved.")
        XCTAssertFalse(app.element("pf530-journal-answered").label.contains("0 of 5"), "The count is read back from the journal (a pre-fill from an earlier test may be saved with it).")
        XCTAssertTrue(app.element("pf530-journal-yes-\(thirdKey)").isSelected, "The saved answer should show as Yes after it is read back.")
        attach(app, "5b morning sheet, answered")
    }

    func testSameAsYesterdayPrefillsTheQuestionsAndCanBeSwitchedOff() throws {
        let app = try launch(open: "journal-morning", extra: ["-Journal530SeedPrevious"])
        let yes = app.element("pf530-journal-yes-\(screenKey)")
        XCTAssertTrue(yes.waitForExistence(timeout: 30), "The first question should have a Yes.")
        let prefilled = NSPredicate(format: "isSelected == true")
        expectation(for: prefilled, evaluatedWith: yes)
        waitForExpectations(timeout: 20)
        XCTAssertTrue(app.element("pf530-journal-no-\(secondKey)").isSelected, "Yesterday's No should be pre-filled too.")
        XCTAssertTrue(app.element("pf530-journal-answered").label.contains("0 of 5"), "A pre-fill is not saved until Save or Done.")
        let toggle = app.element("pf530-journal-same")
        XCTAssertTrue(reveal(toggle, in: app), "The Same as yesterday switch should be reachable.")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let cleared = NSPredicate(format: "isSelected == false")
        expectation(for: cleared, evaluatedWith: app.element("pf530-journal-yes-\(screenKey)"))
        waitForExpectations(timeout: 20)
    }

    // MARK: 5d Evening

    func testEveningSheetShowsTheDayCardAndFourQuestionsAndSavesACount() throws {
        let app = try launch(open: "journal-evening")
        XCTAssertTrue(app.element("pf530-journal-evening").waitForExistence(timeout: 30), "The evening reflection should open over the Plan tab.")
        XCTAssertTrue(app.element("pf530-journal-evening-card").waitForExistence(timeout: 20), "The evening card should show.")
        XCTAssertTrue(app.element("pf530-journal-verdict").exists, "The day's verdict should show.")
        XCTAssertEqual(count(app, prefix: "pf530-journal-row-"), 4, "The evening asks four questions.")
        attach(app, "5d evening reflection")
        let yes = app.element("pf530-journal-yes-\(alcoholKey)")
        XCTAssertTrue(reveal(yes, in: app), "The alcohol question should be reachable.")
        yes.tap()
        let value = app.element("pf530-journal-count-\(alcoholKey)")
        XCTAssertTrue(value.waitForExistence(timeout: 10), "A yes to a count asks how many.")
        XCTAssertEqual(value.label, "1", "How many starts at 1.")
        let plus = app.element("pf530-journal-count-plus-\(alcoholKey)")
        XCTAssertTrue(reveal(plus, in: app), "The stepper should be reachable.")
        plus.tap()
        XCTAssertEqual(app.element("pf530-journal-count-\(alcoholKey)").label, "2", "The stepper should add one.")
        let save = app.element("pf530-journal-save")
        XCTAssertTrue(reveal(save, in: app), "A changed answer should offer Save.")
        save.tap()
        XCTAssertTrue(app.element("pf530-journal-saved").waitForExistence(timeout: 20), "Saving should say it saved.")
        XCTAssertEqual(app.element("pf530-journal-count-\(alcoholKey)").label, "2", "The number saved with the answer is read back from the journal.")
        XCTAssertTrue(app.element("pf530-journal-answered").label.contains("1 of 4"), "The count is read back from the journal.")
    }

    // MARK: 5e Insights

    func testInsightsShowOneClearBehaviourTheNoEffectListAndTheCollectingList() throws {
        let app = try launch(open: "journal-insights")
        XCTAssertTrue(app.element("pf530-insights-body").waitForExistence(timeout: 30), "The insights should open over the Plan tab.")
        XCTAssertEqual(count(app, prefix: "pf530-insight-clear-"), 1, "One behaviour has a clear effect on next-morning Charge.")
        XCTAssertTrue(app.element("pf530-insight-clear-bedtime_late").exists, "A bedtime after 23:30 is the clear one.")
        for id in ["hard_day", "strength_day", "short_sleep"] {
            XCTAssertTrue(app.element("pf530-insight-row-\(id)").exists, "\(id) should be listed under No clear effect.")
        }
        XCTAssertEqual(app.element("pf530-insight-value-hard_day").label, "63 / 48", "No clear effect rows carry with it / without it.")
        XCTAssertEqual(app.element("pf530-insight-counts-\(screenKey)").label, "1 · 0", "Still collecting rows carry the yes and no days so far.")
        XCTAssertTrue(app.element("pf530-insight-series-whoop-charge").exists, "Recovery is read from two devices, each its own chip.")
        attach(app, "5e behaviour insights")
        app.element("pf530-insight-lag-2").tap()
        let changed = NSPredicate(format: "label == %@", "58 / 55")
        expectation(for: changed, evaluatedWith: app.element("pf530-insight-value-hard_day"))
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.element("pf530-insight-clear-bedtime_late").exists, "The morning after shows no clear effect for it.")
    }

    func testAResultRowOpensItsSheetAndDoneClosesIt() throws {
        let app = try launch(open: "journal-insights")
        let row = app.element("pf530-insight-row-bedtime_late")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The clear result should be a row to tap.")
        XCTAssertTrue(reveal(row, in: app), "The row should be reachable.")
        row.tap()
        let sheet = app.element("pf530-insight-detail")
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "A tap should open the sheet behind the result.")
        attach(app, "5e behaviour insight detail")
        let done = app.element("pf530-insight-detail-done")
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The sheet should offer Done.")
        done.tap()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: sheet)
        waitForExpectations(timeout: 20)
    }

    // MARK: 5f Customise

    func testCustomiseListsTheQuestionsAndTheCoachSuggestions() throws {
        let app = try launch(open: "journal-customise")
        XCTAssertTrue(app.element("pf530-journal-customise").waitForExistence(timeout: 30), "Customise should open over the Plan tab.")
        XCTAssertTrue(app.element("pf530-journal-list").waitForExistence(timeout: 20), "The list should show.")
        // A row's identifier is carried by each of its texts, so rows are counted by distinct identifier.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "pf530-journal-list-row-"))
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.identifier)).count, 10, "The list holds the questions.")
        let countLabel = app.element("pf530-journal-list-count").label
        XCTAssertTrue(countLabel.contains("10"), "The list says how many questions.")
        XCTAssertFalse(countLabel.contains("of 10"), "The list no longer says 'of 10'.")
        XCTAssertTrue(app.element("pf530-journal-suggestions").exists, "The coach's suggestions should show while the server sends some.")
        attach(app, "5f customise")
        let add = app.element("pf530-journal-add")
        XCTAssertTrue(reveal(add, in: app), "Add your own should be reachable.")
        XCTAssertFalse(app.element("pf530-journal-add-full").exists, "The full-list explanation no longer exists.")
    }

    // MARK: States

    func testTheMorningSheetSaysSoWhenPaceForgeCannotBeReached() throws {
        let app = try launch(open: "journal-morning", extra: ["-PaceForgeFetchFails"])
        XCTAssertTrue(app.element("plan529-placeholder-failed").waitForExistence(timeout: 30), "With no document and no saved copy the sheet says it failed.")
    }

    func testTheEveningSheetSaysSoWhenTheDocumentIsNotPublished() throws {
        let app = try launch(open: "journal-evening", extra: ["-PaceForgeJournalViewMissing"])
        XCTAssertTrue(app.element("plan529-placeholder-empty").waitForExistence(timeout: 30), "A document that is not served is the empty state.")
    }
}
