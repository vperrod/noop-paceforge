import XCTest
@testable import Strand

/// The job door's pure half: the request body and the inputs of each job (field names as docs/app-job-contract.md has them), how a
/// reply or a refusal reads, and the polling schedule. All values are made up.
final class PaceForgeJobTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    private func assertSame(_ actual: [String: Any]?, _ expected: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual ?? [:]) as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    // MARK: Request body

    func testTheBodyCarriesTheJobNameAndItsInputs() {
        let body = PFJobRequest.body(.saveRpe, inputs: ["data": ["rpe": 7]])
        assertSame(body, ["job": "save-rpe", "inputs": ["data": ["rpe": 7]]])
    }

    func testAJobWithoutInputsSendsAnEmptyObject() {
        assertSame(PFJobRequest.body(.sync), ["job": "sync", "inputs": [String: Any]()])
    }

    func testTheJobNamesAreTheContractsOwn() {
        XCTAssertEqual([PFJobName.sync, .analyzeWorkoutPhoto, .saveRpe, .adjustToday, .coachFeedback, .coach].map { $0.rawValue },
                       ["sync", "analyze-workout-photo", "save-rpe", "adjust-today", "coach-feedback", "coach"])
    }

    // MARK: Activity ids

    func testAGarminIdOfDigitsIsKept() {
        XCTAssertEqual(PFJobInputs.activityID(" 9000000001 "), "9000000001")
    }

    func testARideIdIsKept() {
        XCTAssertEqual(PFJobInputs.activityID("bike:2030-03-13T07:10:00"), "bike:2030-03-13T07:10:00")
    }

    func testABareBikePrefixIsNotAnId() {
        XCTAssertNil(PFJobInputs.activityID("bike:"))
    }

    func testAStrapKeyIsNotAnId() {
        XCTAssertNil(PFJobInputs.activityID("whoop-2030-03-13"))
    }

    func testNoIdIsNoId() {
        XCTAssertNil(PFJobInputs.activityID(nil))
    }

    // MARK: Photo inputs

    func testAPhotoIdIsALowercaseUuid() {
        let id = PFJobInputs.newPhotoID()
        XCTAssertEqual(id, id.lowercased())
    }

    func testAPhotoIdMatchesTheContractsLength() {
        XCTAssertTrue((8...64).contains(PFJobInputs.newPhotoID().count))
    }

    func testAPhotoBoundToAnActivityCarriesTheActivityAndNoDate() {
        let inputs = PFJobInputs.analyzeWorkoutPhoto(photoID: "abc-12345", imageBase64: "QUJD", activityID: "9000000001", date: "2030-03-13")
        assertSame(inputs, ["photo_id": "abc-12345", "image_base64": "QUJD", "auto_attach": true, "activity_id": "9000000001"])
    }

    func testAPhotoWithoutAUsableActivityIsBoundToTheDay() {
        let inputs = PFJobInputs.analyzeWorkoutPhoto(photoID: "abc-12345", imageBase64: "QUJD", activityID: "strap-key", date: "2030-03-13")
        assertSame(inputs, ["photo_id": "abc-12345", "image_base64": "QUJD", "auto_attach": true, "date": "2030-03-13"])
    }

    func testAPhotoWithNeitherIsUnbound() {
        let inputs = PFJobInputs.analyzeWorkoutPhoto(photoID: "abc-12345", imageBase64: "QUJD", activityID: nil, date: nil)
        assertSame(inputs, ["photo_id": "abc-12345", "image_base64": "QUJD"])
    }

    func testAPhotoAsksTheServerToAttachItsReading() {
        let inputs = PFJobInputs.analyzeWorkoutPhoto(photoID: "abc-12345", imageBase64: "QUJD", activityID: nil, date: "2030-03-13")
        XCTAssertEqual(inputs["auto_attach"] as? Bool, true)
    }

    func testAnUnboundPhotoIsSentWithoutAutoAttach() {
        let inputs = PFJobInputs.analyzeWorkoutPhoto(photoID: "abc-12345", imageBase64: "QUJD", activityID: nil, date: nil)
        XCTAssertNil(inputs["auto_attach"])
    }

    // MARK: save-rpe

    func testARatingForAnActivityCarriesTheRatingAndTheActivity() {
        let inputs = PFJobInputs.saveRpe(7, activityID: "9000000001", date: "2030-03-13")
        assertSame(inputs, ["data": ["rpe": 7, "activity_id": "9000000001"]])
    }

    func testARatingForADayCarriesTheDate() {
        let inputs = PFJobInputs.saveRpe(5, activityID: nil, date: "2030-03-13")
        assertSame(inputs, ["data": ["rpe": 5, "date": "2030-03-13"]])
    }

    func testARatingOfZeroIsNotSent() {
        XCTAssertNil(PFJobInputs.saveRpe(0, activityID: "9000000001", date: nil))
    }

    func testARatingOfElevenIsNotSent() {
        XCTAssertNil(PFJobInputs.saveRpe(11, activityID: "9000000001", date: nil))
    }

    func testARatingWithNoActivityAndNoDateIsNotSent() {
        XCTAssertNil(PFJobInputs.saveRpe(6, activityID: nil, date: nil))
    }

    // MARK: adjust-today

    func testTiredSendsOnlyTheMode() {
        assertSame(PFJobInputs.adjustToday(.tired), ["mode": "tired"])
    }

    func testSickSendsOnlyTheMode() {
        assertSame(PFJobInputs.adjustToday(.sick), ["mode": "sick"])
    }

    func testMinutesSendTimeAndTheMinutes() {
        assertSame(PFJobInputs.adjustToday(.minutes(45)), ["mode": "time", "minutes": 45])
    }

    func testFewerThanFifteenMinutesIsNotSent() {
        XCTAssertNil(PFJobInputs.adjustToday(.minutes(10)))
    }

    func testMoreThanTwoHundredFortyMinutesIsNotSent() {
        XCTAssertNil(PFJobInputs.adjustToday(.minutes(241)))
    }

    func testTheConfirmationIsTheServersSummaryWhenItAdjusted() {
        let result = PFJ(data: data(#"{"adjusted": true, "summary": "Shortened to 30 min, easy.", "name": "Tempo"}"#))
        XCTAssertEqual(PFAdjustToday.confirmation(result), "Shortened to 30 min, easy.")
    }

    func testTheConfirmationIsTheServersReasonWhenNothingChanged() {
        let result = PFJ(data: data(#"{"adjusted": false, "reason": "session already fits", "name": "Tempo"}"#))
        XCTAssertEqual(PFAdjustToday.confirmation(result), "session already fits")
    }

    func testAnEmptyResultStillGetsALine() {
        XCTAssertEqual(PFAdjustToday.confirmation(PFJ(nil)), "Nothing changed.")
    }

    // MARK: coach-feedback

    func testAThumbsUpCarriesTheTargetAndTheVerdict() {
        let inputs = PFJobInputs.coachFeedback(kind: "chat", id: "2030-03-13T10:00:00", verdict: .up)
        assertSame(inputs, ["data": ["target": ["kind": "chat", "id": "2030-03-13T10:00:00"], "verdict": "up"]])
    }

    func testAThumbsDownWithAReasonCarriesIt() {
        let inputs = PFJobInputs.coachFeedback(kind: "chat", id: "t1", verdict: .down, reason: " too long ")
        assertSame(inputs, ["data": ["target": ["kind": "chat", "id": "t1"], "verdict": "down", "reason": "too long"]])
    }

    func testAReasonIsCutAtThreeHundredCharacters() {
        let inputs = PFJobInputs.coachFeedback(kind: "chat", id: "t1", verdict: .down, reason: String(repeating: "a", count: 400))
        let reason = ((inputs["data"] as? [String: Any])?["reason"] as? String) ?? ""
        XCTAssertEqual(reason.count, 300)
    }

    func testARatingIsKeptUnderItsKindAndId() {
        XCTAssertEqual(PFCoachFeedback.key(kind: "chat", id: "t1"), "chat:t1")
    }

    // MARK: coach

    func testAnInstructionIsTrimmedAndSentUnderItsField() {
        assertSame(PFJobInputs.coach("  move my long run to Sunday \n"), ["instruction": "move my long run to Sunday"])
    }

    func testAnEmptyInstructionIsNotSent() {
        XCTAssertNil(PFJobInputs.coach("  \n "))
    }

    func testAnInstructionOfTwoThousandCharactersIsSent() {
        XCTAssertNotNil(PFJobInputs.coach(String(repeating: "a", count: 2000)))
    }

    func testAnInstructionOfMoreThanTwoThousandCharactersIsNotSent() {
        XCTAssertNil(PFJobInputs.coach(String(repeating: "a", count: 2001)))
    }

    func testTheCoachJobIsGivenFiveMinutesAndAMargin() {
        XCTAssertEqual(PFJobPolling.deadline(for: .coach), 360)
    }

    func testTheReplyIsTheNewestCoachTurnWhenItIsNew() {
        let chat = [PFChatTurn(role: "coach", text: "Old", ts: "t1"), PFChatTurn(role: "athlete", text: "Move it", ts: "t2"),
                    PFChatTurn(role: "coach", text: " Moved to Sunday. ", ts: "t3")]
        XCTAssertEqual(PFCoachInstruction.reply(in: chat, after: "t1"), "Moved to Sunday.")
    }

    func testNoNewCoachTurnIsNoReply() {
        let chat = [PFChatTurn(role: "coach", text: "Old", ts: "t1")]
        XCTAssertNil(PFCoachInstruction.reply(in: chat, after: "t1"))
    }

    func testAnEmptyTranscriptIsNoReply() {
        XCTAssertNil(PFCoachInstruction.reply(in: [], after: nil))
    }

    func testOnlyNewProposalsAreListed() {
        let kept = PFNeedsItem(id: "proposal:a", kind: .proposal, title: "Old change")
        let added = PFNeedsItem(id: "proposal:b", kind: .proposal, title: "Ease Thursday")
        XCTAssertEqual(PFCoachInstruction.newProposals(before: [kept], after: [kept, added]), ["Ease Thursday"])
    }

    func testANewItemThatIsNotAProposalIsNotListed() {
        let rating = PFNeedsItem(id: "rpe:1", kind: .rpe, title: "Rate it")
        XCTAssertEqual(PFCoachInstruction.newProposals(before: [], after: [rating]), [])
    }

    // MARK: Replies

    func testAFastJobsReplyIsDoneWithItsResult() {
        let reply = PFJobReply.submission(status: 200, body: data(#"{"ok": true, "job": "save-rpe", "id": "11874", "state": "done", "result": {"logged": true}}"#), retryAfter: nil)
        XCTAssertEqual(try? reply.get().state, .done)
    }

    func testTheIdIsReadAsDigits() {
        let reply = PFJobReply.submission(status: 200, body: data(#"{"ok": true, "id": "11874", "state": "queued"}"#), retryAfter: nil)
        XCTAssertEqual(try? reply.get().id, "11874")
    }

    func testAResultIsKeptForTheCaller() {
        let reply = PFJobReply.submission(status: 200, body: data(#"{"id": "1", "state": "done", "result": {"logged": true}}"#), retryAfter: nil)
        XCTAssertEqual((try? reply.get())?.result["logged"].bool, true)
    }

    func testASlowJobsReplyIsQueued() {
        let reply = PFJobReply.submission(status: 200, body: data(#"{"ok": true, "id": "11875", "state": "queued"}"#), retryAfter: nil)
        XCTAssertEqual(try? reply.get().state, .queued)
    }

    func testAnIdThatIsNotDigitsIsUnreadable() {
        let reply = PFJobReply.submission(status: 200, body: data(#"{"id": "../state", "state": "queued"}"#), retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .unreadable)
    }

    func testAReplyWithNoIdIsUnreadable() {
        let reply = PFJobReply.submission(status: 200, body: data(#"{"ok": true}"#), retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .unreadable)
    }

    func testTheLoginPageIsATokenProblem() {
        let reply = PFJobReply.submission(status: 200, body: data("<html>Sign in</html>"), retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .tokenNotAccepted)
    }

    func testAStatusReplyReadsItsState() {
        let reply = PFJobReply.status(status: 200, body: data(#"{"id": "1", "state": "running", "error": null}"#), retryAfter: nil)
        XCTAssertEqual(try? reply.get(), PFJobStatus(state: .running, error: nil))
    }

    func testAFailedStatusCarriesTheRunnersLine() {
        let reply = PFJobReply.status(status: 200, body: data(#"{"id": "1", "state": "failed", "error": "FAILED: no space"}"#), retryAfter: nil)
        XCTAssertEqual(try? reply.get(), PFJobStatus(state: .failed, error: "FAILED: no space"))
    }

    func testAStateTheAppDoesNotKnowKeepsWaiting() {
        XCTAssertEqual(PFJobState("paused"), .running)
    }

    func testOnlyDoneAndFailedAreFinished() {
        XCTAssertEqual([PFJobState.queued, .running, .done, .failed].map { $0.isFinished }, [false, false, true, true])
    }

    // MARK: Refusals

    func testA429CarriesTheRetryAfterSeconds() {
        let reply = PFJobReply.submission(status: 429, body: data(#"{"error": "rate limit"}"#), retryAfter: 1800)
        XCTAssertEqual(reply.failureValue, .rateLimited(retryAfter: 1800))
    }

    func testTheRateLimitMessageSaysHowLong() {
        XCTAssertEqual(PFJobError.rateLimited(retryAfter: 1800).message, "That is a lot of requests for one hour. Try again in 30 min.")
    }

    func testTheRateLimitMessageWithoutASecondsCountSaysLater() {
        XCTAssertEqual(PFJobError.rateLimited(retryAfter: nil).message, "That is a lot of requests for one hour. Try again later.")
    }

    func testA403MeansNoopSyncIsOff() {
        let reply = PFJobReply.submission(status: 403, body: data(#"{"error": "NOOP sync is off"}"#), retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .syncOff)
    }

    func testA401IsATokenProblem() {
        let reply = PFJobReply.submission(status: 401, body: nil, retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .tokenNotAccepted)
    }

    func testA400CarriesTheServersOwnReason() {
        let reply = PFJobReply.submission(status: 400, body: data(#"{"error": "rpe must be 1-10", "message": "rpe must be 1-10"}"#), retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .refused("rpe must be 1-10"))
    }

    func testA409CarriesTheServersOwnReason() {
        let reply = PFJobReply.submission(status: 409, body: data(#"{"error": "No uncompleted session scheduled today."}"#), retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .refused("No uncompleted session scheduled today."))
    }

    func testA413WithoutATextGetsAPlainLine() {
        let reply = PFJobReply.submission(status: 413, body: nil, retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .refused("That was too big to send."))
    }

    func testA500IsServerTrouble() {
        let reply = PFJobReply.submission(status: 500, body: data(#"{"error": "internal"}"#), retryAfter: nil)
        XCTAssertEqual(reply.failureValue, .serverTrouble(500))
    }

    func testAFailedJobWithoutALineStillReads() {
        XCTAssertEqual(PFJobError.failed(nil).message, "PaceForge could not finish that.")
    }

    func testOnlyTroubleThatMayPassKeepsTheWaitGoing() {
        let keeps: [PFJobError] = [.offline, .serverTrouble(502), .unreadable]
        XCTAssertEqual(keeps.map { $0.keepsWaiting }, [true, true, true])
    }

    func testARefusalEndsTheWait() {
        let ends: [PFJobError] = [.tokenNotAccepted, .syncOff, .refused("no"), .rateLimited(retryAfter: 5), .failed(nil), .timedOut, .cancelled]
        XCTAssertEqual(ends.map { $0.keepsWaiting }, Array(repeating: false, count: 7))
    }

    func testNoConnectionReadsAsOffline() {
        XCTAssertEqual(PFJobError.transport(URLError(.notConnectedToInternet)), .offline)
    }

    func testATimeoutReadsAsOffline() {
        XCTAssertEqual(PFJobError.transport(URLError(.timedOut)), .offline)
    }

    func testACancelledRequestReadsAsCancelled() {
        XCTAssertEqual(PFJobError.transport(URLError(.cancelled)), .cancelled)
    }

    // MARK: Client key and the retry list

    func testTheBodyCarriesTheClientKeyAtTheTopLevel() {
        let body = PFJobRequest.body(.saveRpe, inputs: ["data": ["rpe": 7]], clientKey: "abc-123")
        assertSame(body, ["job": "save-rpe", "inputs": ["data": ["rpe": 7]], "client_key": "abc-123"])
    }

    func testAKeyOverSixtyFourCharactersIsNotSent() {
        let body = PFJobRequest.body(.sync, clientKey: String(repeating: "a", count: 65))
        XCTAssertNil(body["client_key"])
    }

    func testANewClientKeyFitsTheContractsLimit() {
        let key = PFJobRequest.newClientKey()
        XCTAssertTrue((1...PFJobRequest.maxClientKeyLength).contains(key.count))
    }

    func testTwoNewClientKeysDiffer() {
        XCTAssertNotEqual(PFJobRequest.newClientKey(), PFJobRequest.newClientKey())
    }

    func testOnlyReplaySafeWritesAreNotKept() {
        let never: [PFJobName] = [.analyzeWorkoutPhoto, .sync, .coach, .saveEvents, .sessionState, .easyModeEnd, .adjustToday, .calendarEdit, .sessionDrop, .easyMode]
        XCTAssertEqual(never.map { $0.isQueueable }, Array(repeating: false, count: never.count))
    }

    func testTheAdditiveWritesAreKept() {
        XCTAssertEqual([PFJobName.saveRpe, .niggleAdd, .niggleResolve, .coachFeedback, .hyroxSimAdd].map { $0.isQueueable },
                       Array(repeating: true, count: 5))
    }

    func testNoAnswerAndPassingTroubleAreSentAgain() {
        let again: [PFJobError] = [.offline, .serverTrouble(503), .rateLimited(retryAfter: 30), .unreadable]
        XCTAssertEqual(again.map { $0.isRetryable }, Array(repeating: true, count: 4))
    }

    func testOnlyNoConnectionStoppingAndARateLimitStopTheRetryPass() {
        let stops: [PFJobError] = [.offline, .cancelled, .rateLimited(retryAfter: 5)]
        XCTAssertEqual(stops.map { $0.stopsRetryPass }, [true, true, true])
    }

    func testServerTroubleAndAnOddAnswerLetThePassGoOn() {
        let goes: [PFJobError] = [.serverTrouble(503), .unreadable]
        XCTAssertEqual(goes.map { $0.stopsRetryPass }, [false, false])
    }

    func testARefusalIsNotSentAgain() {
        let never: [PFJobError] = [.refused("no"), .tokenNotAccepted, .syncOff]
        XCTAssertEqual(never.map { $0.isRetryable }, Array(repeating: false, count: 3))
    }

    func testInputsReadBackAsWrittenWhateverTheKeyOrder() {
        let text = PFJobRetryList.encodeInputs(["b": 2, "a": ["x": 1]])
        XCTAssertEqual(text, PFJobRetryList.encodeInputs(["a": ["x": 1], "b": 2]))
    }

    func testStoredInputsDecodeToTheSameValues() {
        let text = PFJobRetryList.encodeInputs(["data": ["rpe": 7]]) ?? ""
        XCTAssertEqual((PFJobRetryList.decodeInputs(text) ?? [:]) as NSDictionary, ["data": ["rpe": 7]] as NSDictionary)
    }

    private func queued(_ key: String, job: PFJobName = .saveRpe, inputs: String = "{}", age: TimeInterval = 0, now: Date = Date(timeIntervalSince1970: 1_000_000)) -> PFQueuedJob {
        PFQueuedJob(job: job.rawValue, inputs: inputs, clientKey: key, queuedAt: now.addingTimeInterval(-age))
    }

    func testAnEntryOlderThanADayIsDropped() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let kept = PFJobRetryList.live([queued("old", age: 24 * 3600 + 1), queued("new", age: 3600)], now: now)
        XCTAssertEqual(kept.map { $0.clientKey }, ["new"])
    }

    func testAnIdenticalWaitingWriteGivesBackItsKey() {
        let entries = [queued("k1", inputs: #"{"a":1}"#), queued("k2", job: .adjustToday, inputs: #"{"a":1}"#)]
        XCTAssertEqual(PFJobRetryList.key(for: .adjustToday, inputs: #"{"a":1}"#, in: entries), "k2")
    }

    func testADifferentWriteGetsNoKeyBack() {
        XCTAssertNil(PFJobRetryList.key(for: .saveRpe, inputs: #"{"a":2}"#, in: [queued("k1", inputs: #"{"a":1}"#)]))
    }

    func testTheSameKeyIsNeverListedTwice() {
        let once = PFJobRetryList.adding(queued("k1"), to: [queued("k1")])
        XCTAssertEqual(once.count, 1)
    }

    func testTheListKeepsTheNewestTwenty() {
        let full = (0..<PFJobRetryList.maxEntries).map { queued("k\($0)") }
        let after = PFJobRetryList.adding(queued("new"), to: full)
        XCTAssertEqual([after.first?.clientKey, after.last?.clientKey], ["k1", "new"])
    }

    func testRemovingAKeyLeavesTheOthers() {
        let left = PFJobRetryList.removing(clientKey: "k1", from: [queued("k1"), queued("k2")])
        XCTAssertEqual(left.map { $0.clientKey }, ["k2"])
    }

    func testAQueuedWriteTellsTheAthleteItIsSaved() {
        XCTAssertEqual(PFJobError.queued.message, "Couldn't reach PaceForge. Saved on this iPhone; it will be sent when PaceForge is reachable.")
    }

    // MARK: Waiting

    func testTheFirstLookIsAfterTwoSeconds() {
        XCTAssertEqual(PFJobPolling.delay(afterPolls: 0), 2)
    }

    func testLaterLooksAreFiveSecondsApart() {
        XCTAssertEqual([1, 2, 10].map { PFJobPolling.delay(afterPolls: $0) }, [5, 5, 5])
    }

    func testAPhotoReadIsGivenItsExpectedTimeAndAMargin() {
        XCTAssertEqual(PFJobPolling.deadline(for: .analyzeWorkoutPhoto), 330)
    }

    func testASyncIsGivenTwoMinutesAndAMargin() {
        XCTAssertEqual(PFJobPolling.deadline(for: .sync), 180)
    }

    func testTheWaitContinuesBeforeTheDeadline() {
        XCTAssertFalse(PFJobPolling.shouldGiveUp(job: .sync, elapsed: 179))
    }

    func testTheWaitEndsAtTheDeadline() {
        XCTAssertTrue(PFJobPolling.shouldGiveUp(job: .sync, elapsed: 180))
    }

    func testAPhotoBodyGetsALongerTimeoutThanTheSmallWrites() {
        XCTAssertGreaterThan(PFJobName.analyzeWorkoutPhoto.requestTimeout, 20)
    }
}

private extension Result {
    /// The error of a failed result; nil when it succeeded.
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
