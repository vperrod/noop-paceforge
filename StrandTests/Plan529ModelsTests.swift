import XCTest

/// The build-529 contract documents decode into their models. The input is the contract's own examples (`Plan529Contract.json`, copied
/// from the plan-section folder), with the `_note` keys taken out.
final class Plan529ModelsTests: XCTestCase {
    private func contract() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Plan529Contract", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(Self.withoutNotes(root) as? [String: Any])
    }

    private static func withoutNotes(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            return object.filter { !$0.key.hasPrefix("_") }.mapValues(withoutNotes)
        }
        if let list = value as? [Any] { return list.map(withoutNotes) }
        return value
    }

    /// Decodes the example under `key`, and the paths of every non-null value in it that the model did not keep (a misspelt field name).
    private func decode<Doc: Codable>(_ type: Doc.Type, _ key: String) throws -> (doc: Doc, lost: [String]) {
        let example = try XCTUnwrap(try contract()[key], "The contract has no example for \(key).")
        let data = try JSONSerialization.data(withJSONObject: example)
        let doc = try PFPlan529Decoder.make().decode(Doc.self, from: data)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let kept = try JSONSerialization.jsonObject(with: encoder.encode(doc))
        return (doc, Self.lost(example, in: kept, at: key))
    }

    private static func lost(_ original: Any, in kept: Any?, at path: String) -> [String] {
        if original is NSNull { return [] }
        if let object = original as? [String: Any] {
            let keptObject = kept as? [String: Any] ?? [:]
            return object.flatMap { lost($0.value, in: keptObject[$0.key], at: path + "." + $0.key) }
        }
        if let list = original as? [Any] {
            let keptList = kept as? [Any] ?? []
            return list.enumerated().flatMap { lost($0.element, in: keptList.indices.contains($0.offset) ? keptList[$0.offset] : nil, at: path + "[\($0.offset)]") }
        }
        return kept == nil ? [path] : []
    }

    func testEveryContractExampleDecodesAndKeepsEveryField() throws {
        let index = try decode(PFPlanWeekIndexDoc.self, "data/plan-week/index.json")
        let coming = try decode(PFPlanWeekDoc.self, "data/plan-week/2026-W47.json")
        let finished = try decode(PFPlanWeekDoc.self, "data/plan-week/2026-W46.json")
        let season = try decode(PFSeasonDoc.self, "data/season.json")
        let settings = try decode(PFPlanSettingsDoc.self, "data/plan-settings.json")
        let reports = try decode(PFReportsListDoc.self, "data/reports/list.json")
        let daily = try decode(PFDailyShort.self, "data/reports/daily/2026-11-15.json#short")
        let monthly = try decode(PFMonthlyShort.self, "data/reports/monthly/2026-10.json#short")
        let losses = try decode(PFRaceLosses.self, "race results document #losses")
        let inbox = try decode(PFInboxDoc.self, "data/inbox.json")

        XCTAssertEqual(index.doc.current, "2026-W47")
        XCTAssertEqual(coming.doc.changes?.count, 3)
        XCTAssertEqual(coming.doc.days?.count, 7)
        XCTAssertEqual(finished.doc.report?.races?.first?.time, "1:07:41")
        XCTAssertEqual(finished.doc.days?[2].items?.first?.result?.deltaS, 461)
        XCTAssertEqual(season.doc.races?.first?.priorityOptions?.count, 3)
        XCTAssertEqual(season.doc.pastRaces?.first?.result?.time, "1:04:12")
        XCTAssertEqual(settings.doc.youDecide?.first?.value, PFPlanSettingsDoc.Value.number(7))
        XCTAssertEqual(settings.doc.youDecide?[3].value, PFPlanSettingsDoc.Value.list([]))
        XCTAssertEqual(reports.doc.today?.key, "2026-11-15")
        XCTAssertEqual(daily.doc.devices?.first?.source, "Garmin")
        XCTAssertEqual(monthly.doc.tiles?.first?.value, "4 h 38")
        XCTAssertEqual(losses.doc.losses?.first?.segment, "Sandbag lunges")
        XCTAssertEqual(inbox.doc.items?.count, 5)

        let lostPaths = [index.lost, coming.lost, finished.lost, season.lost, settings.lost, reports.lost, daily.lost, monthly.lost,
                         losses.lost, inbox.lost].flatMap { $0 }
        XCTAssertEqual(lostPaths, [], "These contract fields have no property in the models.")
    }

    func testMissingKeysNullsAndUnknownKeysDecode() throws {
        let json = #"{"week": "2026-W47", "phase": null, "days": [{"date": "2026-11-16", "items": [{"kind": "rest", "km": null, "future": 1}]}], "future": {"a": 1}}"#
        let doc = try PFPlan529Decoder.make().decode(PFPlanWeekDoc.self, from: Data(json.utf8))
        XCTAssertEqual(doc.days?.first?.items?.first?.kind, "rest")
    }
}
