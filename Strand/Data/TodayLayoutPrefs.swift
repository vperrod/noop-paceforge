import Foundation
import SwiftUI

// MARK: - Reorderable Today sections (#today-layout)
//
// The liquid Today's sections — the Charge/Effort/Rest hero, the Start-session entry, Synthesis, Key
// Metrics, Workouts, Heart Rate, Recovery Vitals, Your Cards — rendered in one fixed order. This lets the
// user REORDER or HIDE them, with the default being the original order so nothing changes for anyone who
// never customizes Today. Display-only — no metric is computed or stored differently; this only decides
// which already-built sections render and in what sequence.
//
// Stored as a single comma-joined string of section keys in @AppStorage("today.sectionOrder"), the same
// mechanism KeyMetricPrefs uses. The Android side mirrors this byte-identically in TodayLayoutPrefs.kt
// (SharedPreferences "today.sectionOrder"). Every known section stays in the ORDER registry: unknown tokens
// are dropped, and any known section missing from the saved order is INSERTED at its default-order position
// relative to the saved sections — so a section added in a later version surfaces where users expect it
// rather than teleporting to the bottom of an existing saved order.
//
// User visibility is stored separately in "today.hiddenSections". Keeping order and visibility separate is
// intentional: hiding is reversible, a hidden section keeps its stable identity, and a section introduced by
// a future version defaults to visible because it is absent from the explicit hidden set.

/// One reorderable Today section. The rawValue is the stable persisted identifier — keep it byte-identical
/// to the Android `TodaySection` enum so a backup/restore reads the same layout on either OS.
enum TodaySection: String, CaseIterable, Identifiable {
    /// The daily loop's verdict card and its evening wrap (iPhone only; daily-intel.json from PaceForge). Both sit above
    /// the hero by default. The tokens are new, so an Android restore drops them and a saved order inserts them at the top.
    case todaysCall = "todays-call"
    case dayInReview = "day-in-review"
    case hero
    /// The Effort target and Weekly goals cards (with My Day's header and activities, and the Sleep planner card, until build 502): split out
    /// of `hero` so the Heart rate card can sit right under the monitor tiles. iPhone only, like the tokens above: an Android restore drops it and a saved order inserts it right after the hero.
    case myDay = "my-day"
    /// This week's plan progress (my-plan.json from PaceForge) and the user's own chosen metrics. iPhone only, like the two above:
    /// a restore on Android drops the tokens, and a saved order inserts them right after the hero.
    case myPlan = "my-plan"
    case myDashboard = "my-dashboard"
    case liveSession
    case synthesis
    case keyMetrics
    case workouts
    case heartRate
    case recoveryVitals
    case yourCards
    case menstrualCycle
    case journal
    /// Cards hosted from the Trends / Sleep tabs (#today-hosted-cards). Renders the `HostedCardPrefs`
    /// selection in order; empty (and effectively invisible) until the user adds a card in Customise.
    /// Appended LAST so `decodeOrder`'s back-fill lands it predictably for existing saved orders.
    case addedCards

    var id: String { rawValue }

    /// The section's display label in the Arrange sheet — matches the Android `TodaySection.title`.
    var title: String {
        switch self {
        case .todaysCall:     return String(localized: "Assessment and Today's call")
        case .dayInReview:    return String(localized: "Day in review")
        case .hero:           return String(localized: "Charge / Effort / Rest")
        #if os(iOS)
        case .myDay:          return String(localized: "Effort target and weekly goals")
        #else
        case .myDay:          return String(localized: "My Day")
        #endif
        case .myPlan:         return String(localized: "My Plan")
        case .myDashboard:    return String(localized: "My Dashboard")
        case .liveSession:    return String(localized: "Start session")
        case .synthesis:      return String(localized: "Synthesis")
        case .keyMetrics:     return String(localized: "Key Metrics")
        case .workouts:       return String(localized: "Workouts")
        case .heartRate:      return String(localized: "Heart Rate")
        case .recoveryVitals: return String(localized: "Recovery Vitals")
        case .yourCards:      return String(localized: "Your Cards")
        case .menstrualCycle: return String(localized: "Menstrual Cycle")
        case .journal:        return String(localized: "Journal")
        case .addedCards:     return String(localized: "Added Cards")
        }
    }

    /// Sections the iPhone's Today does not draw: Start session, Recovery Vitals, Your Cards (build 502) and My Dashboard (build 504, which gave
    /// the Key Metrics tiles, each opening its detail, their place back: Victor found the rows a poor swap). (`myDay` stays:
    /// on the iPhone it holds the Effort target and the Weekly goals cards only; the My Day timeline is its own tab and the Sleep planner
    /// card moved to the Sleep screen. Adding `.myDay` here would retire those two cards from Today as well.) The cases and their rawValues
    /// stay so the persisted wire format and the Android twin are unchanged, but on iOS they are outside `defaultOrder`,
    /// `TodayLayoutPrefs.decodeOrder` drops them from any saved order and never back-fills them, and so neither Today nor the Arrange
    /// sheet shows them, whatever a phone saved before. Empty on macOS, whose Today keeps every section.
    static let retired: Set<TodaySection> = {
        #if os(iOS)
        return [.liveSession, .recoveryVitals, .yourCards, .myDashboard]
        #else
        return []
        #endif
    }()

    /// The default section order, used when the layout isn't customised. The rings and monitor tiles lead, the Heart rate chart comes
    /// straight after them, then the collapsed text rows (assessment, body signals, Today's call) and My Day. The journal widget (#656)
    /// is last by default, where it was first added, above the data-sources card. `retired` sections are left out.
    static let defaultOrder: [TodaySection] = withoutRetired([
        .hero, .heartRate, .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .liveSession, .synthesis, .keyMetrics, .workouts,
        .recoveryVitals, .yourCards, .menstrualCycle, .journal, .addedCards,
    ])

    /// The orders a phone that never customised Today holds in its saved copy from before the Heart rate card moved up, as `decodeOrder`
    /// reads them (the retired sections are already gone from them on iOS). The first is the earlier default (what the Arrange sheet
    /// wrote on Done); the second is what an order saved before the iPhone-only sections existed (hero first) decodes to. The order
    /// saved while the Heart rate card was already up is the current default. Any of them reads as "not customised" and gets the
    /// current default; any real change is kept as saved.
    static let previousDefaultOrders: [[TodaySection]] = [
        withoutRetired([.todaysCall, .dayInReview, .hero, .myDay, .myPlan, .myDashboard, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate,
                        .recoveryVitals, .yourCards, .menstrualCycle, .journal, .addedCards]),
        withoutRetired([.hero, .todaysCall, .dayInReview, .myDay, .myPlan, .myDashboard, .liveSession, .synthesis, .keyMetrics, .workouts, .heartRate,
                        .recoveryVitals, .yourCards, .menstrualCycle, .journal, .addedCards]),
    ]

    private static func withoutRetired(_ order: [TodaySection]) -> [TodaySection] {
        order.filter { !retired.contains($0) }
    }
}

/// Display-only persistence for the Today section order and visibility. The order registry always contains
/// every known section; `hiddenKey` stores the explicit reversible hidden set. Mirrors Android byte-for-byte, except that a saved order
/// equal to one of `previousDefaultOrders` reads as the current default (iPhone only: Android has none of the iPhone-only sections).
enum TodayLayoutPrefs {
    /// UserDefaults key — a comma-joined list of `TodaySection` rawValues in display order.
    static let orderKey = "today.sectionOrder"
    /// UserDefaults key — a comma-joined list of explicitly hidden `TodaySection` rawValues.
    static let hiddenKey = "today.hiddenSections"

    /// Encode an ordered section list into the stored comma-joined string.
    static func encode(_ sections: [TodaySection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Encode the explicit hidden set in stable list order. The editor passes its Hidden-section order;
    /// rendering treats the decoded value as a set.
    static func encodeHidden(_ sections: [TodaySection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }

    /// Decode the stored string into the FULL ordered section list. An empty/unset string yields the
    /// default order. Unknown and retired tokens are ignored, duplicates collapsed, and any known section missing from
    /// the saved order is INSERTED at its default-order position relative to the saved sections (before the
    /// first saved section that follows it in the default order; appended when none does) — so every
    /// section always renders, and one added in a later app version surfaces where users expect it instead
    /// of teleporting to the bottom of an existing saved order. Twin of the Kotlin `decodeOrder`.
    static func decodeOrder(_ raw: String) -> [TodaySection] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return TodaySection.defaultOrder }
        var saved: [TodaySection] = []
        for token in trimmed.split(separator: ",") {
            if let s = TodaySection(rawValue: token.trimmingCharacters(in: .whitespaces)), !TodaySection.retired.contains(s),
               !saved.contains(s) {
                saved.append(s)
            }
        }
        guard !saved.isEmpty else { return TodaySection.defaultOrder }
        // Iterate allCases (not defaultOrder) so a future case accidentally left out of defaultOrder can
        // never be silently hidden; a section without a default index sorts after everything (no crash —
        // the Kotlin twin's indexOf(-1) degrades the same way). defaultOrder covering allCases is pinned
        // by TodayLayoutPrefsTests on both platforms.
        func defIdx(_ s: TodaySection) -> Int {
            TodaySection.defaultOrder.firstIndex(of: s) ?? TodaySection.defaultOrder.count
        }
        for missing in TodaySection.allCases where !saved.contains(missing) && !TodaySection.retired.contains(missing) {
            let insertAt = saved.firstIndex { defIdx($0) > defIdx(missing) }
            if let insertAt { saved.insert(missing, at: insertAt) } else { saved.append(missing) }
        }
        return TodaySection.previousDefaultOrders.contains(saved) ? TodaySection.defaultOrder : saved
    }

    /// Decode explicitly hidden sections. Empty/unset means nothing is hidden. Unknown tokens are ignored
    /// and duplicates collapsed; unlike `decodeOrder`, missing cases are NOT inserted because absence here
    /// means visible (including a section introduced by a future app version).
    static func decodeHidden(_ raw: String) -> [TodaySection] {
        var seen = Set<TodaySection>()
        var hidden: [TodaySection] = []
        for token in raw.split(separator: ",") {
            if let section = TodaySection(rawValue: token.trimmingCharacters(in: .whitespaces)),
               seen.insert(section).inserted {
                hidden.append(section)
            }
        }
        return hidden
    }

    /// The hidden sections as Today applies them: `decodeHidden`, plus My Day when the saved copy predates it. My Day used to be part of
    /// the Charge / Effort / Rest section, so a phone that hid that section (and whose saved order has no `my-day` token, which the
    /// editor always writes since the split) keeps My Day hidden too.
    static func effectiveHidden(orderRaw: String, hiddenRaw: String) -> [TodaySection] {
        var hidden = decodeHidden(hiddenRaw)
        let savedTokens = orderRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if hidden.contains(.hero), !hidden.contains(.myDay), !savedTokens.contains(TodaySection.myDay.rawValue) {
            hidden.append(.myDay)
        }
        return hidden
    }

    /// The sections Today should render, preserving the full saved order while filtering only the user's
    /// explicit hidden set. At least one visible section is enforced by the editor, not the decoder.
    static func visibleOrder(orderRaw: String, hiddenRaw: String) -> [TodaySection] {
        let hidden = Set(effectiveHidden(orderRaw: orderRaw, hiddenRaw: hiddenRaw))
        return decodeOrder(orderRaw).filter { !hidden.contains($0) }
    }
}
