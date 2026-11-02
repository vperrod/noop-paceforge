import XCTest
@testable import Strand

/// Twin of the Android `TodayLayoutPrefsTest` (#today-layout): default order, encode/decode round-trip,
/// reorder, and the never-hide "insert missing section at its default position" invariant — pinned on both
/// platforms so the byte-identical "today.sectionOrder" wire format can't drift.
final class TodayLayoutPrefsTests: XCTestCase {

    func testEmptyOrUnsetYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(""), TodaySection.defaultOrder)
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("   "), TodaySection.defaultOrder)
    }

    func testEncodeDecodeRoundTripsAReorderedList() {
        let reordered: [TodaySection] = [
            .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .heartRate, .hero, .synthesis,
            .workouts, .journal, .menstrualCycle, .addedCards,
        ]
        let encoded = TodayLayoutPrefs.encode(reordered)
        XCTAssertEqual(encoded, "todays-call,day-in-review,my-day,my-plan,my-dashboard,heartRate,hero,synthesis,workouts,journal,menstrualCycle,addedCards")
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(encoded), reordered)
    }

    /// The v1 upgrade path: an order saved by the FIRST cut (6 sections — no hero/liveSession, which were
    /// pinned then) must surface the two new sections at the TOP (their default position), not teleport
    /// them to the bottom of the user's saved order.
    func testSavedOrderFromFirstCutInsertsHeroAndSessionAtTheirDefaultPosition() {
        let firstCut = "synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(firstCut),
            // The merge lands on the previous default order, which reads as "never customised": the current default.
            TodaySection.defaultOrder
        )
    }

    func testInsertsAnyMissingSectionAtItsDefaultPositionRelativeToSaved() {
        let partial = "heartRate,synthesis,keyMetrics,recoveryVitals"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(partial),
            [.hero, .heartRate, .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .synthesis, .workouts, .menstrualCycle, .journal, .addedCards]
        )
    }

    func testDropsUnknownTokensAndCollapsesDuplicates() {
        let messy = "journal,BOGUS,journal,heartRate, ,heartRate"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(messy),
            [.hero, .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .synthesis, .workouts, .menstrualCycle, .journal, .heartRate, .addedCards]
        )
    }

    func testAllJunkYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("nope,,zzz"), TodaySection.defaultOrder)
    }

    func testHiddenSectionsAreExplicitReversibleAndDeduplicated() {
        let hidden = TodayLayoutPrefs.decodeHidden("workouts,BOGUS,workouts,journal")
        XCTAssertEqual(hidden, [.workouts, .journal])
        XCTAssertEqual(TodayLayoutPrefs.encodeHidden(hidden), "workouts,journal")
    }

    func testVisibleOrderFiltersHiddenWithoutChangingSavedOrder() {
        let order = "heartRate,hero,yourCards,liveSession,synthesis,keyMetrics,workouts,recoveryVitals,journal"
        XCTAssertEqual(
            TodayLayoutPrefs.visibleOrder(orderRaw: order, hiddenRaw: "hero,workouts"),
            [.heartRate, .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .synthesis, .menstrualCycle, .journal, .addedCards]
        )
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(order), [
            .heartRate, .hero, .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .synthesis,
            .workouts, .menstrualCycle, .journal, .addedCards,
        ])
    }

    /// An order saved while a previous default was in force (the Arrange sheet writes one on Done) is not a customisation: it follows
    /// the new default. Any real change to it is kept as saved.
    func testSavedPreviousDefaultOrdersFollowTheNewDefault() {
        for previous in TodaySection.previousDefaultOrders {
            XCTAssertEqual(TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.encode(previous)), TodaySection.defaultOrder)
        }
    }

    func testCustomisedOrderIsNotReplacedByTheNewDefault() {
        var custom = TodaySection.previousDefaultOrders[0]
        custom.swapAt(custom.firstIndex(of: .workouts) ?? 0, custom.firstIndex(of: .synthesis) ?? 0)
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(TodayLayoutPrefs.encode(custom)), custom)
    }

    /// Build 502 took Start session, Key Metrics, Recovery Vitals and Your Cards off Today. The order the Arrange sheet saved while they
    /// were in the default reads as "not customised" and follows the new default.
    func testBuild501DefaultOrderSavedOnThePhoneFollowsTheNewDefault() {
        let saved = "hero,heartRate,todays-call,day-in-review,my-day,my-plan,my-dashboard,liveSession,synthesis,keyMetrics,workouts,recoveryVitals,yourCards,menstrualCycle,journal,addedCards"
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(saved), TodaySection.defaultOrder)
    }

    /// A customised order keeps the user's sequence of the sections that remain; the retired ones just drop out.
    func testCustomisedOrderDropsTheRetiredSectionsAndKeepsTheRest() {
        let saved = "hero,heartRate,todays-call,day-in-review,my-day,my-plan,my-dashboard,liveSession,workouts,keyMetrics,synthesis,recoveryVitals,yourCards,menstrualCycle,journal,addedCards"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(saved),
            [.hero, .heartRate, .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .workouts, .synthesis, .menstrualCycle, .journal, .addedCards]
        )
    }

    /// Whatever a phone saved, a retired section is neither in the order nor visible, even when it was never hidden.
    func testRetiredSectionsNeverReturnWhateverIsSaved() {
        for raw in ["", "liveSession,keyMetrics,recoveryVitals,yourCards", TodayLayoutPrefs.encode(TodaySection.allCases)] {
            let order = TodayLayoutPrefs.decodeOrder(raw)
            XCTAssertTrue(TodaySection.retired.isDisjoint(with: order), raw)
            XCTAssertTrue(TodaySection.retired.isDisjoint(with: TodayLayoutPrefs.visibleOrder(orderRaw: raw, hiddenRaw: "")), raw)
        }
    }

    func testNewOrPreviouslyMissingSectionsDefaultToVisible() {
        XCTAssertTrue(
            TodayLayoutPrefs.visibleOrder(
                orderRaw: "synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards",
                hiddenRaw: "workouts"
            ).contains(.journal)
        )
    }

    /// defaultOrder plus the retired sections must cover EVERY case: the never-hide merge iterates the cases that are not retired, so a
    /// case missing from the default order could otherwise be mis-sorted.
    func testDefaultOrderAndRetiredSectionsCoverEveryCaseOnce() {
        XCTAssertEqual(Set(TodaySection.defaultOrder).union(TodaySection.retired), Set(TodaySection.allCases))
        XCTAssertTrue(Set(TodaySection.defaultOrder).isDisjoint(with: TodaySection.retired))
        XCTAssertEqual(TodaySection.defaultOrder.count + TodaySection.retired.count, TodaySection.allCases.count)
    }

    func testSectionRawKeysAreStableAndUnique() {
        let raws = TodaySection.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "raw keys must be unique (they're the persisted identity)")
        // Pin the exact wire strings. todays-call, day-in-review, my-day, my-plan and my-dashboard are iPhone-only; every other one must match the
        // Android TodaySection byte-for-byte, and Android's decoder drops the five it does not know.
        XCTAssertEqual(
            raws,
            ["todays-call", "day-in-review", "hero", "my-day", "my-plan", "my-dashboard", "liveSession", "synthesis", "keyMetrics", "workouts", "heartRate", "recoveryVitals", "yourCards", "menstrualCycle", "journal", "addedCards"]
        )
    }

    func testEditableLayoutHidesAndRestoresWithoutDeleting() {
        var draft = EditableLayoutDraft(
            visible: TodaySection.defaultOrder,
            allItems: TodaySection.defaultOrder
        )

        draft.hide(.workouts)
        XCTAssertFalse(draft.visible.contains(.workouts))
        XCTAssertEqual(draft.hidden, [.workouts])

        draft.show(.workouts)
        XCTAssertEqual(draft.visible.last, .workouts)
        XCTAssertTrue(draft.hidden.isEmpty)
        XCTAssertEqual(Set(draft.visible), Set(TodaySection.defaultOrder))
    }

    func testEditableLayoutKeepsAtLeastOneItemVisible() {
        var draft = EditableLayoutDraft(visible: [KeyMetric.hrv], hidden: KeyMetric.defaultOrder.filter { $0 != .hrv })
        draft.hide(.hrv)
        XCTAssertEqual(draft.visible, [.hrv])
    }
}
