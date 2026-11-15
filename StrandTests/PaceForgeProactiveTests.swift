import XCTest
@testable import Strand

/// proactive.json: lenient decoding, the messages Today shows, and the Insights groups.
final class PaceForgeProactiveTests: XCTestCase {
    private func doc(_ messages: [[String: Any]]) -> PFProactiveDoc? {
        PFProactiveDoc.parse(PFJ(["messages": messages]))
    }

    private func message(_ id: String, _ date: String, _ family: String) -> [String: Any] {
        ["id": id, "date": date, "text": "text \(id)", "family": family]
    }

    func testUnknownFamilyAndToneReadAsOtherAndInfo() throws {
        let parsed = try XCTUnwrap(doc([["id": "a", "date": "2030-03-13", "text": "t", "family": "new_kind", "tone": "loud"]]))
        XCTAssertEqual(parsed.messages.first?.tone, .info)
    }

    func testMissingOptionalFieldsStillDecode() throws {
        let parsed = try XCTUnwrap(doc([["id": "a", "date": "2030-03-13", "text": "t"]]))
        XCTAssertNil(parsed.messages.first?.source)
    }

    func testMessageWithoutTextIsDropped() throws {
        let parsed = try XCTUnwrap(doc([["id": "a", "date": "2030-03-13"]]))
        XCTAssertEqual(parsed.messages, [])
    }

    func testTodayShowsOnlyTodayAndYesterdayNewestFirst() throws {
        let parsed = try XCTUnwrap(doc([message("old", "2030-03-10", "works"), message("y", "2030-03-12", "works"),
                                        message("t", "2030-03-13", "works")]))
        XCTAssertEqual(parsed.forToday("2030-03-13").map(\.id), ["t", "y"])
    }

    func testTodayShowsAtMostTwo() throws {
        let parsed = try XCTUnwrap(doc([message("a", "2030-03-13", "works"), message("b", "2030-03-13", "costs"),
                                        message("c", "2030-03-12", "trend")]))
        XCTAssertEqual(parsed.forToday("2030-03-13").map(\.id), ["a", "b"])
    }

    func testGroupsFollowTheHeadingOrderAndLeaveOutEmptyOnes() throws {
        let parsed = try XCTUnwrap(doc([message("r", "2030-03-12", "race"), message("t", "2030-03-11", "rhythm"),
                                        message("i", "2030-03-10", "improvement"), message("w", "2030-03-13", "works")]))
        XCTAssertEqual(parsed.groups("2030-03-13").map { $0.group.title }, ["What is working", "Trends to watch", "Races"])
    }

    func testGroupHoldsWorksAndImprovementNewestFirst() throws {
        let parsed = try XCTUnwrap(doc([message("i", "2030-03-10", "improvement"), message("w", "2030-03-13", "works")]))
        XCTAssertEqual(parsed.groups("2030-03-13").first?.messages.map { $0.id }, ["w", "i"])
    }

    func testMessagesOlderThanFourteenDaysAreNotListed() throws {
        let parsed = try XCTUnwrap(doc([message("old", "2030-02-27", "works")]))
        XCTAssertEqual(parsed.groups("2030-03-13").count, 0)
    }

    func testRecordingSourceNamesGarminTheStrapAndAppleHealth() {
        XCTAssertEqual(PFRecordingSource.name(forActivityName: "Running"), "Garmin")
        XCTAssertEqual(PFRecordingSource.name(forActivityName: "Running \u{00B7} NOOP strap"), "WHOOP strap")
        XCTAssertEqual(PFRecordingSource.name(forActivityName: "Running \u{00B7} Apple Health via NOOP"), "Apple Health")
    }
}
