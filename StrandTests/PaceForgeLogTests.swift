import XCTest
@testable import Strand

/// Logging a body measure or a field test from the app: the phrase the sheet builds, the checks before a request
/// goes out, and how the server's answer reads. All values are made up.
final class PaceForgeLogTests: XCTestCase {
    private func body(_ text: String) -> Data { Data(text.utf8) }

    // MARK: A tape number

    func testPlainNumberIsAccepted() {
        XCTAssertEqual(PFLog.normalizedCm("92.5"), "92.5")
    }
    func testCommaDecimalBecomesADot() {
        XCTAssertEqual(PFLog.normalizedCm("92,5"), "92.5")
    }
    func testTrailingCmIsDropped() {
        XCTAssertEqual(PFLog.normalizedCm(" 88 cm "), "88")
    }
    func testOneDigitIsRefused() {
        XCTAssertNil(PFLog.normalizedCm("9"))
    }
    func testFourDigitsAreRefused() {
        XCTAssertNil(PFLog.normalizedCm("1000"))
    }
    func testThreeDecimalsAreRefused() {
        XCTAssertNil(PFLog.normalizedCm("92.555"))
    }
    func testTrailingDotIsRefused() {
        XCTAssertNil(PFLog.normalizedCm("92."))
    }
    func testLettersAreRefused() {
        XCTAssertNil(PFLog.normalizedCm("ninety"))
    }
    func testTwoDotsAreRefused() {
        XCTAssertNil(PFLog.normalizedCm("9.2.5"))
    }
    func testEmptyIsRefused() {
        XCTAssertNil(PFLog.normalizedCm("  "))
    }

    // MARK: The tape phrase

    func testPhraseListsFilledSitesInTheWebCardsOrder() {
        let phrase = PFLog.tapePhrase(["thigh": "58", "waist": "92,5", "hips": "98"])
        XCTAssertEqual(phrase, "waist 92.5 hips 98 thigh 58")
    }
    func testEmptyFieldsAreLeftOut() {
        XCTAssertEqual(PFLog.tapePhrase(["waist": "90", "hips": "  ", "chest": ""]), "waist 90")
    }
    func testNothingFilledGivesNoPhrase() {
        XCTAssertNil(PFLog.tapePhrase([:]))
    }
    func testAnUnreadableFieldIsNamedInTheProblem() {
        XCTAssertEqual(PFLog.tapeProblem(["waist": "90", "hips": "x"]), "Hips: type the number in centimetres, like 92.5.")
    }
    func testFilledAndEmptyFieldsAreNoProblem() {
        XCTAssertNil(PFLog.tapeProblem(["waist": "90", "hips": ""]))
    }
    func testTheSitesAreTheOnesTheTapeCardShows() {
        XCTAssertEqual(PFLog.tapeSites.map { $0.key }, PFTape.siteOrder)
    }

    // MARK: A field-test phrase

    func testSpacesAndLineBreaksFoldToSingleSpaces() {
        XCTAssertEqual(PFLog.cleanedPhrase("  squat   140\n x 5 "), "squat 140 x 5")
    }
    func testEmptyPhraseCannotBeSent() {
        XCTAssertFalse(PFLog.canSend(""))
    }
    func testPhraseOfTwoHundredCharactersCanBeSent() {
        XCTAssertTrue(PFLog.canSend(String(repeating: "a", count: 200)))
    }
    func testPhraseOfTwoHundredAndOneCannotBeSent() {
        XCTAssertFalse(PFLog.canSend(String(repeating: "a", count: 201)))
    }
    func testEveryExamplePhraseFitsTheLimit() {
        XCTAssertTrue(PFLog.fieldTests.allSatisfy { PFLog.canSend($0.example) })
    }
    func testEveryLiftExampleHasWeightAndReps() {
        let lifts = PFLog.fieldTests.filter { $0.title.contains("weight x reps") }
        XCTAssertTrue(!lifts.isEmpty && lifts.allSatisfy { $0.example.contains(" x ") })
    }

    // MARK: The request

    func testRequestBodyCarriesTheKindAndTheText() {
        XCTAssertEqual(PFLog.requestBody(kind: .fieldTest, text: "grip 52 kg"), ["kind": "field_test", "text": "grip 52 kg"])
    }
    func testTapeKindIsSentAsTape() {
        XCTAssertEqual(PFLog.requestBody(kind: .tape, text: "waist 90")["kind"], "tape")
    }

    // MARK: The answer

    func testASaveShowsTheServersConfirmation() {
        let outcome = PFLogOutcome.from(status: 200, body: body(#"{"ok": true, "message": "Tape logged for 2030-03-13: waist 92.5 cm."}"#))
        XCTAssertEqual(outcome, .saved("Tape logged for 2030-03-13: waist 92.5 cm."))
    }
    func testASaveWithNoMessageStillSaysSaved() {
        XCTAssertEqual(PFLogOutcome.from(status: 200, body: body(#"{"ok": true}"#)), .saved("Saved."))
    }
    func testARefusalShowsTheServersReason() {
        let outcome = PFLogOutcome.from(status: 400, body: body(#"{"message": "Not logged: squat: use 1-12 reps for an estimate"}"#))
        XCTAssertEqual(outcome, .refused("Not logged: squat: use 1-12 reps for an estimate"))
    }
    func testARefusalIsNeverASave() {
        XCTAssertFalse(PFLogOutcome.from(status: 400, body: body(#"{"message": "no"}"#)).isSaved)
    }
    func testTheRateLimitWithoutAMessageGetsAPlainLine() {
        XCTAssertEqual(PFLogOutcome.from(status: 429, body: nil), .refused("That is a lot of entries for one hour. Try again later."))
    }
    func testAnUnknownFailureNamesTheStatus() {
        XCTAssertEqual(PFLogOutcome.from(status: 502, body: body("<html>bad gateway</html>")),
                       .refused("PaceForge could not save that (HTTP 502)."))
    }
    func testTheLoginPageIsNotASave() {
        XCTAssertFalse(PFLogOutcome.from(status: 200, body: body("  <!doctype html><html>sign in</html>")).isSaved)
    }
    func testAnOverlongServerMessageIsCut() {
        let long = String(repeating: "x", count: 900)
        XCTAssertEqual(PFLogOutcome.from(status: 400, body: body(#"{"message": "\#(long)"}"#)).message.count, 400)
    }
    func testNoConnectionIsSaidPlainlyAndSavesNothing() {
        XCTAssertEqual(PFLogOutcome.unreachable.isSaved, false)
    }
}
