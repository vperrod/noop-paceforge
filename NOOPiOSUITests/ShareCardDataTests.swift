import ImageIO
import UniformTypeIdentifiers
import XCTest

/// The figures behind the share cards (StrandiOS/Share/ShareCardData.swift, compiled into this bundle). Plain unit
/// checks that launch no app. Every number is made up.
final class ShareCardDataTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func values(_ day: String, charge: Double? = nil, sleep: Double? = nil, effort: Double? = nil,
                        hrv: Double? = nil, rhr: Double? = nil) -> ShareDayValues {
        ShareDayValues(day: day, charge: charge, sleepMin: sleep, effort: effort, hrv: hrv, restingHr: rhr)
    }

    private func figures(_ shown: ShareDayValues, history: [ShareDayValues] = [], rows: [ShareStrapRow]? = nil,
                         strapLiveEffort: Double? = nil, hidesScores: Bool = false) -> ShareDayFigures {
        ShareDayFigures.make(shown: shown, history: history, rows: rows ?? self.rows(history + [shown]),
                             strapLiveEffort: strapLiveEffort, liveProvider: "WHOOP", hidesScores: hidesScores,
                             calendar: calendar)
    }

    private func rows(_ days: [ShareDayValues], _ provider: String = "WHOOP") -> [ShareStrapRow] {
        days.map { ShareStrapRow(values: $0, provider: provider) }
    }

    private func figure(_ value: Double, average: Double? = nil, _ provider: String = "WHOOP") -> ShareFigure {
        ShareFigure(value: value, average: average, provider: provider)
    }

    private let earlier = ["2030-03-10", "2030-03-11", "2030-03-12"]

    func testAverageLeavesOutTheShownDayAndLaterDays() {
        let history = zip(earlier, [40.0, 50, 60]).map { values($0.0, charge: $0.1) }
            + [values("2030-03-13", charge: 99), values("2030-03-14", charge: 1)]
        XCTAssertEqual(figures(values("2030-03-13", charge: 99), history: history).charge,
                       figure(99, average: 50))
    }

    func testAverageCoversThirtyDaysBeforeTheShownDay() {
        // 11 Feb is the 30th day before 13 Mar 2030; 10 Feb is the 31st.
        let history = [values("2030-02-10", hrv: 900), values("2030-02-11", hrv: 30)]
            + earlier.map { values($0, hrv: 50) }
        XCTAssertEqual(figures(values("2030-03-13", hrv: 70), history: history).hrv?.average, 45)
    }

    func testTooFewEarlierDaysGiveNoAverage() {
        let history = [values("2030-03-11", rhr: 40), values("2030-03-12", rhr: 42)]
        XCTAssertEqual(figures(values("2030-03-13", rhr: 44), history: history).restingHr, figure(44))
    }

    func testMissingAndZeroReadingsAreLeftOff() {
        let result = figures(values("2030-03-13", sleep: 0, hrv: nil, rhr: 44))
        XCTAssertEqual(result, ShareDayFigures(restingHr: figure(44)))
    }

    func testZeroEffortIsAScore() {
        XCTAssertEqual(figures(values("2030-03-13", effort: 0)).effort?.value, 0)
    }

    func testAFigureNoStoredRowCarriesIsLeftOff() {
        let shown = values("2030-03-13", charge: 77, rhr: 44)
        let result = figures(shown, rows: rows([values("2030-03-13", charge: 12, rhr: 44)]))
        XCTAssertEqual(result, ShareDayFigures(restingHr: figure(44)))
    }

    func testAverageSkipsDaysFilledByAnotherSource() {
        let history = ["2030-03-09", "2030-03-10", "2030-03-11", "2030-03-12"].map { values($0, rhr: 40) }
        var merged = history
        merged[0].restingHr = 80
        let shown = values("2030-03-13", rhr: 44)
        // The stored rows have no resting HR on 9 Mar: the 80 came from somewhere else.
        let stored = [values("2030-03-09")] + Array(history.dropFirst()) + [shown]
        XCTAssertEqual(figures(shown, history: merged, rows: rows(stored)).restingHr?.average, 40)
    }

    func testAverageNeverMixesTwoDevices() {
        let older = ["2030-03-07", "2030-03-08", "2030-03-09"].map { values($0, hrv: 90) }
        let recent = earlier.map { values($0, hrv: 50) }
        let shown = values("2030-03-13", hrv: 70)
        let result = figures(shown, history: older + recent, rows: rows(older) + rows(recent + [shown], "Oura"))
        XCTAssertEqual(result.hrv, figure(70, average: 50, "Oura"))
    }

    func testAnEmptyDeviceListIsNotOnlyWhoop() {
        XCTAssertFalse(ShareStrapRow.isOnlyWhoop(brands: []))
    }

    func testAnOlderDayIsNamedAfterTheDeviceThatMeasuredIt() {
        let shown = values("2030-03-09", hrv: 90)
        XCTAssertEqual(figures(shown, rows: rows([shown])).sourceLine, "WHOOP data")
    }

    func testSourceLineNamesEveryDeviceOnTheCard() {
        let hrvRow = values("2030-03-13", hrv: 70)
        let rhrRow = values("2030-03-13", rhr: 44)
        let result = figures(values("2030-03-13", hrv: 70, rhr: 44), rows: rows([hrvRow], "Oura") + rows([rhrRow]))
        XCTAssertEqual(result.sourceLine, "Oura + WHOOP data")
    }

    func testLiveStrapEffortStaysWithoutAStoredRow() {
        XCTAssertEqual(figures(values("2030-03-13", effort: 12), rows: [], strapLiveEffort: 12).effort, figure(12))
    }

    func testHiddenScoresStayOffTheCard() {
        let result = figures(values("2030-03-13", charge: 77, sleep: 400, effort: 55), hidesScores: true)
        XCTAssertEqual(result, ShareDayFigures(sleepMin: figure(400)))
    }

    func testCardWithNoFigureHasNoSourceLine() {
        XCTAssertNil(figures(values("2030-03-13")).sourceLine)
    }

    private let cardPixels = CGSize(width: 960, height: 1620)

    private func jpeg(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func decodedSize(_ data: Data) throws -> CGSize {
        let image = try XCTUnwrap(SharePhoto.downscaled(data, covering: cardPixels))
        return CGSize(width: image.width, height: image.height)
    }

    func testLargePhotoIsDecodedJustLargeEnoughToCoverTheCard() throws {
        XCTAssertEqual(try decodedSize(jpeg(width: 4000, height: 3000)), CGSize(width: 2160, height: 1620))
    }

    func testTurnedPhotoComesOutUprightAndCoversTheCard() throws {
        // Orientation 6: stored landscape, shown portrait.
        XCTAssertEqual(try decodedSize(jpeg(width: 4000, height: 3000, orientation: 6)), CGSize(width: 1215, height: 1620))
    }

    func testSmallPhotoIsNotEnlarged() throws {
        XCTAssertEqual(try decodedSize(jpeg(width: 400, height: 300)), CGSize(width: 400, height: 300))
    }

    func testUnreadablePhotoGivesNothing() {
        XCTAssertNil(SharePhoto.downscaled(Data("not a picture".utf8), covering: cardPixels))
    }

    func testWorkoutLeavesOutMissingAndZeroReadings() {
        let result = ShareWorkoutFigures(durationS: 1111, avgHr: nil, maxHr: 0, kcal: 222, distanceM: 0, effort: nil)
        XCTAssertEqual(result, ShareWorkoutFigures(durationS: 1111, avgHr: nil, maxHr: nil, kcal: 222, distanceM: nil,
                                                   effort: nil))
    }
}
