import XCTest
@testable import Strand

/// Coach extras: the response-length instruction, the "Ask about this" question, the history of past
/// conversations and the local feedback log. All values are made up.
final class CoachExtrasTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func messages(_ first: String = "How is my charge trending?") -> [CoachStoredMessage] {
        [CoachStoredMessage(role: "user", text: first), CoachStoredMessage(role: "assistant", text: "Steady.")]
    }

    // MARK: Response length

    func testDefaultLengthLeavesThePromptUntouched() {
        XCTAssertEqual(CoachResponseLength.standard.systemPrompt(base: "Be a coach."), "Be a coach.")
    }

    func testCondensedLengthAppendsItsInstructionAfterTheBasePrompt() {
        let prompt = CoachResponseLength.condensed.systemPrompt(base: "Be a coach.")
        XCTAssertTrue(prompt.hasPrefix("Be a coach.\n\n"))
    }

    func testCondensedInstructionAsksForShortReplies() {
        XCTAssertTrue(CoachResponseLength.condensed.promptAddition.contains("condensed"))
    }

    func testLengthSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "coach-length-test")!
        defaults.removePersistentDomain(forName: "coach-length-test")
        CoachResponseLength.save(.condensed, to: defaults)
        XCTAssertEqual(CoachResponseLength.current(defaults), .condensed)
    }

    func testUnsetLengthIsTheDefault() {
        let defaults = UserDefaults(suiteName: "coach-length-unset")!
        defaults.removePersistentDomain(forName: "coach-length-unset")
        XCTAssertEqual(CoachResponseLength.current(defaults), .standard)
    }

    // MARK: Ask about this

    func testQuestionNamesTheMetric() {
        XCTAssertTrue(CoachAskPrompt.question(about: "HRV").contains("my HRV"))
    }

    func testQuestionWithNoMetricIsStillAQuestion() {
        XCTAssertTrue(CoachAskPrompt.question(about: "  ").hasSuffix("?"))
    }

    // MARK: History

    func testTitleIsTheFirstQuestion() {
        XCTAssertEqual(CoachHistory.title(from: messages()), "How is my charge trending?")
    }

    func testLongTitleIsCutWithAnEllipsis() {
        let title = CoachHistory.title(from: messages(String(repeating: "word ", count: 30)))
        XCTAssertLessThanOrEqual(title.count, CoachHistory.maxTitleLength)
        XCTAssertTrue(title.hasSuffix("\u{2026}"))
    }

    func testTitleIsOneLine() {
        XCTAssertEqual(CoachHistory.title(from: messages("Line one\nline two")), "Line one line two")
    }

    func testConversationWithNoQuestionIsNotKept() {
        XCTAssertNil(CoachHistory.record(from: [CoachStoredMessage(role: "assistant", text: "Today's brief")], now: now, id: "a"))
    }

    func testConversationWithAQuestionIsKept() {
        XCTAssertEqual(CoachHistory.record(from: messages(), now: now, id: "a")?.messageCount, 2)
    }

    func testNewestConversationIsFirst() {
        let older = CoachHistory.record(from: messages("old"), now: now, id: "old")!
        let newer = CoachHistory.record(from: messages("new"), now: now.addingTimeInterval(60), id: "new")!
        XCTAssertEqual(CoachHistory.archiving([older], record: newer).map(\.id), ["new", "old"])
    }

    func testArchivingTheSameIdReplacesIt() {
        let first = CoachHistory.record(from: messages("one"), now: now, id: "a")!
        let second = CoachHistory.record(from: messages("two"), now: now.addingTimeInterval(60), id: "a")!
        XCTAssertEqual(CoachHistory.archiving([first], record: second).map(\.title), ["two"])
    }

    func testTheSameChatPutAwayTwiceIsOneEntry() {
        let first = CoachHistory.record(from: messages("same"), now: now, id: "a")!
        let second = CoachHistory.record(from: messages("same"), now: now.addingTimeInterval(60), id: "b")!
        XCTAssertEqual(CoachHistory.archiving([first], record: second).map(\.id), ["b"])
    }

    func testHistoryIsCappedAtThirtyConversations() {
        var list: [CoachConversationRecord] = []
        for index in 0..<35 {
            let record = CoachHistory.record(from: messages("q\(index)"), now: now.addingTimeInterval(Double(index)), id: "id\(index)")!
            list = CoachHistory.archiving(list, record: record)
        }
        XCTAssertEqual(list.count, 30)
    }

    func testCappingKeepsTheNewest() {
        var list: [CoachConversationRecord] = []
        for index in 0..<35 {
            let record = CoachHistory.record(from: messages("q\(index)"), now: now.addingTimeInterval(Double(index)), id: "id\(index)")!
            list = CoachHistory.archiving(list, record: record)
        }
        XCTAssertEqual(list.first?.id, "id34")
    }

    func testRemovingADeletedConversation() {
        let record = CoachHistory.record(from: messages(), now: now, id: "a")!
        XCTAssertEqual(CoachHistory.removing([record], id: "a"), [])
    }

    func testHistoryRoundTripsThroughAFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-history-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let record = CoachHistory.record(from: messages(), now: now, id: "a")!
        CoachLocalFiles.save([record], to: url)
        XCTAssertEqual(CoachLocalFiles.load([CoachConversationRecord].self, from: url), [record])
    }

    func testMissingFileReadsAsEmpty() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-missing-\(UUID().uuidString).json")
        XCTAssertEqual(CoachLocalFiles.load([CoachConversationRecord].self, from: url), [])
    }

    // MARK: Feedback

    func testFeedbackReasonsAreTheFourNamed() {
        XCTAssertEqual(CoachFeedbackReason.allCases.map(\.label), ["Inaccurate", "Unhelpful", "Off-topic", "Unsafe"])
    }

    func testThumbsDownKeepsItsReason() {
        let entry = CoachFeedbackEntry(messageId: "m", rating: .down, reason: .inaccurate, at: now)
        XCTAssertEqual(CoachFeedbackLog.recording([], entry: entry).first?.reason, .inaccurate)
    }

    func testThumbsUpDropsAnyReason() {
        let entry = CoachFeedbackEntry(messageId: "m", rating: .up, reason: .unsafe, at: now)
        XCTAssertNil(CoachFeedbackLog.recording([], entry: entry).first?.reason)
    }

    func testNewFeedbackOnTheSameReplyReplacesTheOld() {
        var list = CoachFeedbackLog.recording([], entry: CoachFeedbackEntry(messageId: "m", rating: .up, reason: nil, at: now))
        list = CoachFeedbackLog.recording(list, entry: CoachFeedbackEntry(messageId: "m", rating: .down, reason: .offTopic, at: now))
        XCTAssertEqual(list.map(\.rating), [.down])
    }

    func testFeedbackIsLookedUpByReply() {
        let list = CoachFeedbackLog.recording([], entry: CoachFeedbackEntry(messageId: "m", rating: .down, reason: .unhelpful, at: now))
        XCTAssertEqual(CoachFeedbackLog.entry(for: "m", in: list)?.reason, .unhelpful)
    }

    func testFeedbackLogIsCapped() {
        var list: [CoachFeedbackEntry] = []
        for index in 0..<(CoachFeedbackLog.maxEntries + 10) {
            list = CoachFeedbackLog.recording(list, entry: CoachFeedbackEntry(messageId: "m\(index)", rating: .up, reason: nil, at: now))
        }
        XCTAssertEqual(list.count, CoachFeedbackLog.maxEntries)
    }

    func testRemovingFeedbackClearsTheThumb() {
        let list = CoachFeedbackLog.recording([], entry: CoachFeedbackEntry(messageId: "m", rating: .up, reason: nil, at: now))
        XCTAssertNil(CoachFeedbackLog.entry(for: "m", in: CoachFeedbackLog.removing(list, messageId: "m")))
    }

    func testFeedbackFileKeepsNoReplyText() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-feedback-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        CoachLocalFiles.save([CoachFeedbackEntry(messageId: "m", rating: .down, reason: .inaccurate, at: now)], to: url)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertFalse(text.contains("text"))
    }
}
