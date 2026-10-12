import XCTest
@testable import Strand

/// The saved sync endpoint ends in `noop/push` (sometimes behind `api/`); PaceForge pages hang off the
/// instance root, so a wrong strip lands on `api/api/state`, where the server answers 200 with its login page.
final class PaceForgeURLTests: XCTestCase {
    private func url(_ endpoint: String) -> String {
        SelfHostedPushClient.paceForgeURL(from: URL(string: endpoint)!, path: "api/state").absoluteString
    }

    func testEndpointWithApiNoopPush() {
        XCTAssertEqual(url("https://pf.example.test/paceforge/api/noop/push"),
                       "https://pf.example.test/paceforge/api/state")
    }

    func testEndpointWithNoopPush() {
        XCTAssertEqual(url("https://pf.example.test/paceforge/noop/push"),
                       "https://pf.example.test/paceforge/api/state")
    }

    func testEndpointWithInstancePrefix() {
        XCTAssertEqual(url("https://pf.example.test/pf/athlete/noop/push"),
                       "https://pf.example.test/pf/athlete/api/state")
    }
}
