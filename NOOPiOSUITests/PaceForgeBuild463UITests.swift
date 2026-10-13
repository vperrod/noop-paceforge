import XCTest

/// Simulator checks for the build-463 screens: Add measurement (tape and field test), Today Customise,
/// the heart-rate-recovery card, the Where you stand add button and the lift exercise filters. Like the other
/// PaceForge UI tests they serve the synthetic PaceForgeFixture.json (made-up values only).
final class PaceForgeBuild463UITests: XCTestCase {
    private func launch(extraArguments: [String] = [], fixture: Bool = true) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--demo-seed")
        app.launchArguments.append(contentsOf: extraArguments)
        if fixture {
            app.launchArguments.append("-PaceForgeFixture")
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PaceForgeFixture", withExtension: "json"),
                                    "The synthetic fixture should be bundled with the UI tests.")
            app.launchEnvironment["PF_FIXTURE_JSON"] = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openSegment(_ app: XCUIApplication, _ title: String) throws {
        let tab = app.tabBars.buttons["PaceForge"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "The PaceForge tab should be present.")
        tab.tap()
        let segments = app.segmentedControls["pf-segments"]
        XCTAssertTrue(segments.waitForExistence(timeout: 15), "The PaceForge segmented control should load from the fixture.")
        segments.buttons[title].tap()
    }

    /// Scrolls down until the element can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 14) -> Bool {
        for _ in 0..<(maxSwipes * 3) {
            if element.exists && element.isHittable { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        if !(element.exists && element.isHittable) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "hierarchy after a failed reveal"
            tree.lifetime = .keepAlways
            add(tree)
        }
        return element.exists && element.isHittable
    }

    /// Scrolls a sheet with whole-screen swipes: the short drag in `reveal` does not move a sheet's form.
    private func swipeToReveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }

    // MARK: Add measurement

    func testAddMeasurementSheetTakesATapeAndAFieldTest() throws {
        let app = try launch()
        try openSegment(app, "Body")
        let open = element(app, "pf-add-tape-button")
        XCTAssertTrue(reveal(open, in: app, maxSwipes: 20), "The Body tape card should offer Add measurement.")
        attach(app, "80 Body tape card with Add measurement")
        open.tap()
        XCTAssertTrue(element(app, "pf-add-sheet").waitForExistence(timeout: 10), "The Add measurement sheet should open.")
        let waist = element(app, "pf-add-tape-waist")
        XCTAssertTrue(waist.waitForExistence(timeout: 5), "The tape side should list the sites.")
        attach(app, "81 Add measurement tape")
        waist.tap()
        waist.typeText("92.5")
        attach(app, "81 Add measurement tape filled")
        app.segmentedControls["pf-add-kind"].buttons["Field test"].tap()
        let text = element(app, "pf-add-fieldtest-text")
        XCTAssertTrue(text.waitForExistence(timeout: 5), "The field-test side should have its text field.")
        attach(app, "82 Add measurement field test")
        text.tap()
        text.typeText("push-ups 35")
        attach(app, "82 Add measurement field test filled")
        XCTAssertTrue(element(app, "pf-add-save").isEnabled, "A valid phrase should enable Save.")
        element(app, "pf-add-done").tap()
    }

    // MARK: Today Customise

    func testTodayCustomiseMovesAndPinsACard() throws {
        let app = try launch()
        try openSegment(app, "Today")
        let customise = element(app, "pf-today-customise")
        XCTAssertTrue(customise.waitForExistence(timeout: 10), "Today should offer Customise.")
        attach(app, "83 Today before Customise")
        customise.tap()
        XCTAssertTrue(element(app, "pf-today-customise-help").waitForExistence(timeout: 5), "Customise should explain itself.")
        attach(app, "83 Today Customise on")
        let downs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pf-arrange-down-'"))
        XCTAssertGreaterThan(downs.count, 0, "Every card should carry a Down button while Customise is on.")
        var moved = false
        for index in 0..<downs.count {
            let button = downs.element(boundBy: index)
            if button.isEnabled && button.isHittable { button.tap(); moved = true; break }
        }
        XCTAssertTrue(moved, "A card should be movable down.")
        attach(app, "84 Today card moved down")
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pf-arrange-pin-'"))
        for index in 0..<pins.count {
            let button = pins.element(boundBy: index)
            if button.isEnabled && button.isHittable { button.tap(); break }
        }
        attach(app, "84 Today card pinned")
        XCTAssertTrue(element(app, "pf-today-customise-reset").waitForExistence(timeout: 5),
                      "A saved arrangement should offer PaceForge's order again.")
        app.swipeUp()
        attach(app, "84 Today Customise scrolled")
        for _ in 0..<2 { app.swipeDown() }
        customise.tap()
        attach(app, "85 Today Customise done")
    }

    // MARK: Heart rate recovery

    private func openFirstResults(_ app: XCUIApplication) throws {
        try openSegment(app, "This week")
        let done = app.buttons["pf-workout-s-mon"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The completed easy run should be listed.")
        done.tap()
    }

    func testHeartRateRecoveryCardShowsTheContextCaption() throws {
        let app = try launch()
        try openFirstResults(app)
        let context = element(app, "pf-hrr1-context")
        XCTAssertTrue(reveal(context, in: app, maxSwipes: 20), "A first-minute drop should carry its context caption.")
        attach(app, "86 HRR card")
    }

    func testHeartRateRecoveryCardListsGarminsReadings() throws {
        let app = try launch(extraArguments: ["-PaceForgeHRRGarmin"])
        try openFirstResults(app)
        let reading = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'after the stop'")).firstMatch
        XCTAssertTrue(reveal(reading, in: app, maxSwipes: 20), "Garmin's readings after the stop should be listed.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'shown as Garmin Connect shows it'")).firstMatch.exists,
                      "The card should carry Garmin's label.")
        attach(app, "87 HRR card Garmin readings")
    }

    // MARK: Where you stand

    func testWhereYouStandOffersLogAFieldTest() throws {
        let app = try launch()
        try openSegment(app, "Insights")
        let button = element(app, "pf-add-field_test-button")
        XCTAssertTrue(reveal(button, in: app, maxSwipes: 20), "Where you stand should offer Log a field test.")
        attach(app, "88 Where you stand add button")
        button.tap()
        XCTAssertTrue(element(app, "pf-add-sheet").waitForExistence(timeout: 10), "The Add measurement sheet should open.")
        XCTAssertTrue(element(app, "pf-add-fieldtest-text").waitForExistence(timeout: 5),
                      "It should open on the field-test side.")
        attach(app, "88 Log a field test sheet")
        element(app, "pf-add-done").tap()
    }

    // MARK: Lift exercise filters

    func testLiftExercisePickerFiltersByMuscleGroupAndEquipment() throws {
        let app = try launch(fixture: false)
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 30))
        more.tap()
        let body = app.buttons["Body"]
        if body.waitForExistence(timeout: 10), (body.value as? String) != "Expanded" {
            _ = reveal(body, in: app, maxSwipes: 8)
            body.tap()
        }
        let lift = app.staticTexts["Lift Log"]
        XCTAssertTrue(reveal(lift, in: app, maxSwipes: 10), "More should list Lift Log.")
        lift.tap()
        let newProgram = app.buttons["New program"]
        XCTAssertTrue(newProgram.waitForExistence(timeout: 15), "Lift Log should offer New program.")
        newProgram.tap()
        let name = app.textFields["Upper A"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "The program editor should open.")
        name.tap()
        name.typeText("Push day")
        let addFirst = app.buttons["Add exercise"]
        XCTAssertTrue(reveal(addFirst, in: app, maxSwipes: 6), "The editor should offer Add exercise.")
        addFirst.tap()
        let exercise = app.textFields["Incline dumbbell press"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 10), "The exercise sheet should open.")
        exercise.tap()
        exercise.typeText("Bench press")
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() }
        let barbell = element(app, "lift-equipment-barbell")
        XCTAssertTrue(swipeToReveal(barbell, in: app), "The exercise sheet should tag equipment.")
        barbell.tap()
        attach(app, "89 Lift exercise equipment tag")
        let save = app.buttons["Save exercise"]
        XCTAssertTrue(swipeToReveal(save, in: app), "The exercise sheet should save.")
        save.tap()
        let addSecond = app.buttons["Add exercise"]
        XCTAssertTrue(addSecond.waitForExistence(timeout: 10), "Back in the editor, Add exercise should still be there.")
        XCTAssertTrue(reveal(addSecond, in: app, maxSwipes: 6))
        addSecond.tap()
        XCTAssertTrue(element(app, "lift-filter-bar").waitForExistence(timeout: 10),
                      "With an exercise remembered, the picker should show the muscle-group and equipment filters.")
        attach(app, "90 Lift exercise filters")
        let barbellChip = element(app, "lift-filter-equipment-barbell")
        XCTAssertTrue(reveal(barbellChip, in: app, maxSwipes: 6))
        barbellChip.tap()
        attach(app, "90 Lift filter Barbell")
        // "Bench press" also labels the program line behind the sheet, so the suggestion list is asserted
        // through its own heading: "Used before" is only drawn while the filtered list has rows.
        let usedBefore = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Used before'")).firstMatch
        XCTAssertTrue(usedBefore.waitForExistence(timeout: 5), "The barbell filter should keep the remembered barbell exercise.")
        barbellChip.tap()
        let push = element(app, "lift-filter-region-push")
        XCTAssertTrue(reveal(push, in: app, maxSwipes: 6))
        push.tap()
        // The remembered exercise has no muscle tag, so a muscle-group filter leaves it out. The program sheet
        // only drops the list; the "no match" note belongs to the in-session sheet.
        XCTAssertFalse(usedBefore.waitForExistence(timeout: 3),
                       "An exercise with no muscle tag is left out of a muscle-group filter.")
        attach(app, "90 Lift filter Push empty")
    }
}
