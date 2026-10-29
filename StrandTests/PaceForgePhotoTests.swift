import XCTest
@testable import Strand

/// A workout photo as the app sees it: the size it is shrunk to, how PaceForge's draft of the reading reads, and what its retry queue
/// says about an earlier photo. All values are made up.
final class PaceForgePhotoTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: Size

    func testABigPhotoIsShrunkToSixteenHundredOnTheLongEdge() {
        XCTAssertEqual(PFPhotoSize.longEdge(width: 4032, height: 3024), 1600)
    }

    func testAPortraitPhotoIsMeasuredOnItsHeight() {
        XCTAssertEqual(PFPhotoSize.longEdge(width: 3024, height: 4032), 1600)
    }

    func testASmallPhotoKeepsItsOwnLongEdge() {
        XCTAssertEqual(PFPhotoSize.longEdge(width: 1200, height: 900), 1200)
    }

    func testAPhotoExactlyAtTheLimitIsKept() {
        XCTAssertEqual(PFPhotoSize.longEdge(width: 1600, height: 1000), 1600)
    }

    func testAnUnknownSizeFallsBackToTheLimit() {
        XCTAssertEqual(PFPhotoSize.longEdge(width: 0, height: 0), 1600)
    }

    func testTheJpegQualityIsPointEight() {
        XCTAssertEqual(PFPhotoSize.jpegQuality, 0.8)
    }

    // MARK: The draft

    func testNoFileYetIsStillReading() {
        XCTAssertEqual(PFPhotoDraft.stage(from: nil), .reading)
    }

    func testAnEmptyDraftIsStillReading() {
        XCTAssertEqual(PFPhotoDraft.stage(from: data("{}")), .reading)
    }

    func testAFirstReadWithASummaryIsRead() {
        let draft = data(#"{"photo_path": "data/photos/abc.jpg", "summary": "Strength circuit, 5 rounds", "exercises": [{"name": "Squat"}]}"#)
        XCTAssertEqual(PFPhotoDraft.stage(from: draft), .read("Strength circuit, 5 rounds"))
    }

    func testAReadWithOnlyExercisesNamesTheFirstThree() {
        let draft = data(#"{"exercises": [{"name": "Squat"}, {"name": "Row"}, {"name": "Lunge"}, {"name": "Plank"}]}"#)
        XCTAssertEqual(PFPhotoDraft.stage(from: draft), .read("Squat, Row, Lunge"))
    }

    func testABusyModelIsRetrying() {
        let draft = data(#"{"error": "model busy", "retrying": true, "state": "retrying", "attempts": 1}"#)
        XCTAssertEqual(PFPhotoDraft.stage(from: draft), .retrying)
    }

    func testARetryingFlagWithoutAStateIsRetrying() {
        XCTAssertEqual(PFPhotoDraft.stage(from: data(#"{"error": "model busy", "retrying": true}"#)), .retrying)
    }

    func testAnErrorWithoutRetryingIsCouldNotRead() {
        XCTAssertEqual(PFPhotoDraft.stage(from: data(#"{"photo_path": "data/photos/abc.jpg", "error": "not a workout"}"#)), .couldNotRead)
    }

    func testAGivenUpPhotoIsCouldNotRead() {
        XCTAssertEqual(PFPhotoDraft.stage(from: data(#"{"state": "gave_up", "attempts": 6}"#)), .couldNotRead)
    }

    func testAPhotoReadAfterARetryIsRead() {
        XCTAssertEqual(PFPhotoDraft.stage(from: data(#"{"state": "read", "summary": "Sled day", "attempts": 2}"#)), .read("Sled day"))
    }

    // MARK: The retry queue

    func testAPhotoIsFiledUnderItsActivity() {
        XCTAssertEqual(PFPhotoPending.key(activityID: "9000000001", date: "2030-03-13"), "9000000001")
    }

    func testAPhotoWithoutAnActivityIsFiledUnderItsDay() {
        XCTAssertEqual(PFPhotoPending.key(activityID: nil, date: "2030-03-13"), "date:2030-03-13")
    }

    func testNoActivityAndNoDateHasNoKey() {
        XCTAssertNil(PFPhotoPending.key(activityID: nil, date: nil))
    }

    func testAnEarlierPhotoStillBeingRetriedIsRetrying() {
        let pending = data(#"{"9000000001": {"photo_id": "abc", "state": "retrying", "attempts": 2}}"#)
        XCTAssertEqual(PFPhotoPending.stage(from: pending, key: "9000000001"), .retrying)
    }

    func testAnEarlierPhotoGivenUpOnIsCouldNotRead() {
        let pending = data(#"{"date:2030-03-13": {"photo_id": "abc", "state": "gave_up"}}"#)
        XCTAssertEqual(PFPhotoPending.stage(from: pending, key: "date:2030-03-13"), .couldNotRead)
    }

    func testAnEarlierPhotoThatWasReadSaysNothing() {
        let pending = data(#"{"9000000001": {"photo_id": "abc", "state": "read"}}"#)
        XCTAssertNil(PFPhotoPending.stage(from: pending, key: "9000000001"))
    }

    func testAnotherActivitysPhotoSaysNothing() {
        let pending = data(#"{"9000000002": {"photo_id": "abc", "state": "retrying"}}"#)
        XCTAssertNil(PFPhotoPending.stage(from: pending, key: "9000000001"))
    }

    func testNoQueueFileSaysNothing() {
        XCTAssertNil(PFPhotoPending.stage(from: nil, key: "9000000001"))
    }
}
