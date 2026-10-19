import XCTest
@testable import Strand

/// The Needs you list: how the server's document reads, the bodies POST /app/answer takes, the treadmill input checks and
/// how the server's reply reads. All values are made up.
final class PaceForgeNeedsYouTests: XCTestCase {
    private func json(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    private let document = """
    {"items":[
     {"id":"treadmill_pace:91","kind":"treadmill_pace","title":"Treadmill run","available":true,"meaning":"30 min.",
      "metric":{"activity_id":"91","duration_min":30,"structured":true,
        "last":{"speed_kmh":null,"incline_pct":1,"blocks":[{"reps":4,"speed_kmh":14.5,"dist_m":1000.0}],"rest_kmh":8},
        "limits":{"speed_kmh":[5,20],"pace_s_per_km":[180,800],"incline_pct":[0,10]}},
      "ref":{"kind":"treadmill_pace","activity_id":"91"}},
     {"id":"rpe:s1","kind":"rpe","title":"How hard?","available":true,"ref":{"kind":"rpe","session_id":"s1"}},
     {"id":"proposal:pace:ab","kind":"proposal","title":"New pace","available":true,"meaning":"Easy pace 5:30-6:00","ref":{"kind":"proposal","id":"pace:ab"}},
     {"id":"feel:2030-03-13","kind":"feel","title":"Feel","available":true,"metric":{"date":"2030-03-13"},"ref":{"kind":"feel"}},
     {"id":"future:1","kind":"something_new","title":"?","available":true},
     {"id":"proposal:hidden","kind":"proposal","title":"Hidden","available":false,"ref":{"kind":"proposal","id":"hidden"}}
    ]}
    """

    func testEveryKnownKindIsReadInOrder() {
        XCTAssertEqual(PFNeedsParse.items(json(document)).map { $0.id },
                       ["treadmill_pace:91", "rpe:s1", "proposal:pace:ab", "feel:2030-03-13"])
    }

    func testTreadmillRunCarriesTheServersLimits() {
        let run = PFNeedsParse.items(json(document))[0].run
        XCTAssertEqual(run?.speedKmh, 5...20)
    }

    func testTreadmillLastKeepsItsBlocks() {
        let last = PFNeedsParse.items(json(document))[0].run?.last
        XCTAssertEqual(last?.blocks, [PFTreadmillBlock(reps: 4, speedKmh: 14.5, distM: 1000, durS: nil)])
    }

    func testAnEmptyOrMissingDocumentHasNoItems() {
        XCTAssertEqual(PFNeedsParse.items(json("{\"items\":[]}")).count + PFNeedsParse.items(PFJ(nil)).count, 0)
    }

    func testSameAsLastSendsBlocksForAStructuredRun() {
        let last = PFNeedsParse.items(json(document))[0].run!.last!
        let body = PFNeedsAnswer.sameAsLast(activityID: "91", last: last, preferBlocks: true).body
        XCTAssertEqual((body["blocks"] as? [[String: Any]])?.count, 1)
    }

    func testSameAsLastSendsNoSingleSpeedWithBlocks() {
        let last = PFNeedsParse.items(json(document))[0].run!.last!
        let body = PFNeedsAnswer.sameAsLast(activityID: "91", last: last, preferBlocks: true).body
        XCTAssertNil(body["speed_kmh"])
    }

    func testRpeNamesExactlyOneId() {
        let body = PFNeedsAnswer.rpe(7, activityID: "91", sessionID: "s1").body
        XCTAssertNil(body["session_id"])
    }

    func testProposalBodyUsesAcceptAndDismiss() {
        XCTAssertEqual(PFNeedsAnswer.proposal(id: "x", accept: false).body["decision"] as? String, "dismiss")
    }

    func testTheSameAnswerHasTheSameSignature() {
        let a = PFNeedsAnswer.treadmillSpeed(activityID: "1", kmh: 11.6, inclinePct: 1)
        XCTAssertEqual(a.signature(for: "i"), PFNeedsAnswer.treadmillSpeed(activityID: "1", kmh: 11.6, inclinePct: 1).signature(for: "i"))
    }

    func testSpeedOutsideTheLimitsIsNotSendable() {
        let run = PFTreadmillRun(name: nil, durationMin: 30, structured: false, last: nil)
        XCTAssertNil(PFTreadmillInput.check(run: run, activityID: "1", useKmh: true, value: "30", incline: "").answer)
    }

    func testPaceMinutesAndSecondsBecomeSeconds() {
        XCTAssertEqual(PFTreadmillInput.paceSeconds("5:10"), 310)
    }

    func testPaceWithOneDigitSecondsIsRefused() {
        XCTAssertNil(PFTreadmillInput.paceSeconds("5:1"))
    }

    func testAnEmptySpeedHasNoHint() {
        let run = PFTreadmillRun(name: nil, durationMin: 30, structured: false, last: nil)
        XCTAssertNil(PFTreadmillInput.check(run: run, activityID: "1", useKmh: true, value: " ", incline: "").hint)
    }

    func testSavedReplyCarriesTheFreshList() {
        let reply = Data("{\"ok\":true,\"message\":\"Done.\",\"needs_you\":{\"items\":[]}}".utf8)
        XCTAssertEqual(PFAnswerOutcome.from(status: 200, data: reply).fresh?.count, 0)
    }

    func testFollowupReplyShowsTheServersMessage() {
        let reply = Data("{\"ok\":false,\"state\":\"followup\",\"message\":\"Those blocks are longer than the run.\"}".utf8)
        XCTAssertEqual(PFAnswerOutcome.from(status: 422, data: reply).message, "Those blocks are longer than the run.")
    }

    func testALoginPageIsNotASave() {
        XCTAssertFalse(PFAnswerOutcome.from(status: 401, data: Data("<html>".utf8)).isSaved)
    }
}
