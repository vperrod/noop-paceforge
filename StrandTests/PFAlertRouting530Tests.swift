import XCTest
@testable import Strand

/// Build 530, APP-4: where a journal alert opens, and what its notification carries.
final class PFAlertRouting530Tests: XCTestCase {
    private func item(window: String?, route: String = "journal") -> PFInboxDoc.Item {
        PFInboxDoc.Item(id: "journal:2026-11-16:\(window ?? "none")", ts: nil, kind: "journal", notify: true, title: "T", body: "B",
                        listTitle: nil, listSub: nil, link: PFInboxDoc.Link(route: route), window: window)
    }

    func testTheMorningQuestionsOpenTheMorningSheet() {
        XCTAssertEqual(PFInboxRoute529(link: PFInboxLogic529.resolvedLink(of: item(window: "morning"))), .journalMorning)
    }

    func testTheEveningQuestionsOpenTheEveningSheet() {
        XCTAssertEqual(PFInboxRoute529(link: PFInboxLogic529.resolvedLink(of: item(window: "evening"))), .journalEvening)
    }

    func testTheTapOnTheAfternoonQuestionOpensTheEveningSheet() {
        XCTAssertEqual(PFInboxRoute529(link: PFInboxLogic529.resolvedLink(of: item(window: "day"))), .journalAfternoon)
    }

    func testTheOldRouteNamesStillOpenTheirSheets() {
        XCTAssertEqual(PFInboxRoute529(link: PFInboxDoc.Link(route: "journal_morning")), .journalMorning)
    }

    func testAnInboxRowForAMorningQuestionOpensTheMorningSheet() {
        let rows = PFInboxLogic529.rows(items: [item(window: "morning")], legacy: [])
        XCTAssertEqual(PFInboxRoute529(link: rows[0].link), .journalMorning)
    }

    func testAnotherRouteIsLeftAlone() {
        XCTAssertEqual(PFInboxLogic529.resolvedLink(of: item(window: "day", route: "week"))?.route, "week")
    }

    func testTheNotificationCarriesTheResolvedRoute() {
        let userInfo = PFInboxPayload529.userInfo(for: item(window: "morning"))
        XCTAssertEqual(userInfo["pf.route"] as? String, "journal_morning")
    }

    func testTheNotificationCarriesTheItemKind() {
        let userInfo = PFInboxPayload529.userInfo(for: item(window: "morning"))
        XCTAssertEqual(userInfo[PFInboxPayload529.itemKindKey] as? String, "journal")
    }

    func testTheAfternoonQuestionUsesTheLockScreenCategory() {
        XCTAssertEqual(PFAlertCategory530.identifier(for: item(window: "day")), PFAlertCategory530.journalDay)
    }
}
