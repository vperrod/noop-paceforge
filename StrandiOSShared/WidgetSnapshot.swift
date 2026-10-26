import Foundation

/// Small, Codable glance snapshot shared between the iOS app and its widget/Live-Activity extension
/// via an App Group. The app writes it; the widget reads it. Keeping it tiny avoids any cross-process
/// database access — the widget never opens SQLite.
public struct WidgetSnapshot: Codable, Equatable {
    public var recovery: Int?    // Charge (0–100)
    public var bpm: Int?
    public var batteryPct: Int?
    public var bonded: Bool
    public var updated: Date
    // Richer glance fields (#446). All OPTIONAL with nil defaults so a snapshot written by an OLDER app
    // build (which never encoded these keys) still decodes — Codable fills a missing optional with nil.
    public var effort: Int?      // Effort / strain on NOOP's 0–100 axis (ring fill is always this / 100)
    public var rest: Int?        // Rest (sleep_performance) score, 0–100
    public var hrv: Int?         // HRV (ms), whole-number for the glance
    public var restingHr: Int?   // Resting heart rate (bpm)
    // #313 Effort scale for the glance. Pre-formatted at publish time because the widget extension
    // cannot read the app's plain UserDefaults `effort.scale` key (it lives outside the App Group).
    // When nil (older snapshot), the widget falls back to whole-number `effort` on the 0–100 axis.
    public var effortDisplay: String?
    /// True when `effortDisplay` is on WHOOP's 0–21 axis; false/nil means 0–100. Accessibility only.
    public var effortWhoop: Bool?
    /// The last `HrTrace.windowSec` of heart rate, one point per minute, for the trace widget (#1957).
    ///
    /// Folded in by `save()` rather than by the callers that build a snapshot, which is the twin of the
    /// Android store owning it: nothing that publishes had to learn the retention rule. Optional so a
    /// snapshot written by an older build still decodes.
    public var hrSeries: [HrPoint]?
    /// Today's hourly stress curve for the stress widget (#2040), earliest to latest.
    ///
    /// Unlike `hrSeries` this is NOT folded by `save()`. It arrives complete from the publish that
    /// scored the day, so a publish either carries a whole day or says nothing about stress at all, and
    /// the live fast path simply carries the loaded value forward untouched. Optional so a snapshot
    /// written by an older build still decodes.
    public var stressSeries: [StressPoint]?
    /// Local day number `stressSeries` was scored for, or nil when no curve has been published.
    ///
    /// Read back as the staleness check: a curve from any day but today is dropped rather than drawn,
    /// so the widget cannot show yesterday's afternoon under today's date while waiting for the first
    /// scorable hour after midnight.
    public var stressDay: Int?
    // Effort target (the "Effort target" widget). All pre-formatted at publish time on the user's Effort
    // scale, like `effortDisplay`, because the extension has no access to the app's scale preference or to
    // the repository. Optional so a snapshot from an older build still decodes. `effort...` on the stored
    // 0-100 axis are for the gauge fill; the texts are what is printed.
    /// TODAY's Effort on the stored 0-100 axis. Not `effort`, which follows the carried-over anchor day.
    public var effortTargetEffort: Int?
    public var effortTargetEffortText: String?
    public var effortBandLow: Int?
    public var effortBandHigh: Int?
    /// "55-70" (en dash), on the user's scale.
    public var effortBandText: String?
    /// "13-28 to go", "In your range", "Above range by 5" or "Not scored yet".
    public var effortToGo: String?
    /// The logical day (yyyy-MM-dd) the target was built for, and when.
    public var effortTargetDay: String?
    public var effortTargetAt: Date?
    /// Settings > Hide numbers, as the app last published them. The values above stay in the file; the widget
    /// draws `redactedForDisplay()` instead, so flipping a switch needs no recompute and flipping it back
    /// brings the numbers straight back. Optional so a snapshot from an older build still decodes.
    public var scoresHidden: Bool?
    public var bodyHidden: Bool?

    public init(recovery: Int?, bpm: Int?, batteryPct: Int?, bonded: Bool, updated: Date,
                effort: Int? = nil, rest: Int? = nil, hrv: Int? = nil, restingHr: Int? = nil,
                effortDisplay: String? = nil, effortWhoop: Bool? = nil,
                hrSeries: [HrPoint]? = nil, stressSeries: [StressPoint]? = nil,
                stressDay: Int? = nil,
                effortTargetEffort: Int? = nil, effortTargetEffortText: String? = nil,
                effortBandLow: Int? = nil, effortBandHigh: Int? = nil, effortBandText: String? = nil,
                effortToGo: String? = nil, effortTargetDay: String? = nil, effortTargetAt: Date? = nil) {
        self.recovery = recovery
        self.bpm = bpm
        self.batteryPct = batteryPct
        self.bonded = bonded
        self.updated = updated
        self.effort = effort
        self.rest = rest
        self.hrv = hrv
        self.restingHr = restingHr
        self.effortDisplay = effortDisplay
        self.effortWhoop = effortWhoop
        self.hrSeries = hrSeries
        self.stressSeries = stressSeries
        self.stressDay = stressDay
        self.effortTargetEffort = effortTargetEffort
        self.effortTargetEffortText = effortTargetEffortText
        self.effortBandLow = effortBandLow
        self.effortBandHigh = effortBandHigh
        self.effortBandText = effortBandText
        self.effortToGo = effortToGo
        self.effortTargetDay = effortTargetDay
        self.effortTargetAt = effortTargetAt
    }

    /// This snapshot as a widget draws it: with Charge, Effort and Rest (and the Effort target built from them)
    /// taken out while the scores are hidden, so no face can print what it was asked to hide.
    public func redactedForDisplay() -> WidgetSnapshot {
        guard scoresHidden == true else { return self }
        var out = self
        out.recovery = nil
        out.effort = nil
        out.rest = nil
        out.effortDisplay = nil
        out.effortTargetEffort = nil
        out.effortTargetEffortText = nil
        out.effortBandLow = nil
        out.effortBandHigh = nil
        out.effortBandText = nil
        out.effortToGo = nil
        return out
    }

    /// How old the Effort target may be before the widget stops showing it.
    public static let effortTargetMaxAge: TimeInterval = 6 * 60 * 60
    /// The hour the logical day rolls over (04:00 local), the same boundary as `Repository.logicalDayKey`.
    public static let logicalDayRolloverHour = 4

    /// yyyy-MM-dd of the logical day for `date`: the calendar date of `date` minus the rollover hours.
    /// The extension cannot reach `Repository`, so the boundary is mirrored here, in the device's own zone
    /// (`Calendar.current`'s, which `Repository.localDayKey` also follows); a caller passes a calendar only
    /// to pin the zone in tests.
    public static func logicalDayKey(_ date: Date, calendar: Calendar = .current,
                                     rolloverHour: Int = logicalDayRolloverHour) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date.addingTimeInterval(-Double(rolloverHour) * 3_600))
    }

    /// Whether the Effort target describes today and was written recently enough to show. Resolved on read,
    /// like `stressCurve`: nothing runs at midnight to clear the App Group, so a yesterday's band is dropped
    /// where it would be drawn, and a file the app stopped refreshing goes stale after `effortTargetMaxAge`.
    public func effortTargetIsFresh(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let day = effortTargetDay, let at = effortTargetAt else { return false }
        return day == WidgetSnapshot.logicalDayKey(now, calendar: calendar)
            && now.timeIntervalSince(at) >= 0
            && now.timeIntervalSince(at) <= WidgetSnapshot.effortTargetMaxAge
    }

    /// The curve to DRAW: what was published, unless it belongs to a day that is over.
    ///
    /// Resolved on read rather than cleared on write, the same discipline `HrTrace.prune` applies to
    /// age: nothing runs at midnight to tidy the App Group, so the check has to happen where the value
    /// is used. Calendar is injectable so a test can cross a rollover without waiting for one.
    public func stressCurve(now: Date = Date(), calendar: Calendar = .current) -> [StressPoint] {
        guard let stressDay, let stressSeries,
              stressDay == WidgetSnapshot.localDayNumber(now, calendar: calendar) else { return [] }
        return stressSeries
    }

    /// Days since the epoch on the LOCAL calendar, corresponding to Kotlin's
    /// `LocalDate.toEpochDay()` built-in.
    ///
    /// Counted by the calendar rather than by dividing the day's start by 86 400. That arithmetic is
    /// wrong on a DST day and measurably so: walking a year of local noons, `Europe/London` produces
    /// ONE day whose number equals the previous day's, because its winter offset is UTC and a
    /// 23-hour day then lands inside the same 86 400-second bucket. On that day the widget would have
    /// read yesterday's curve as today's and drawn it, which is the one thing this number exists to
    /// prevent. The calendar knows how long each local day actually was.
    public static func localDayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        let epoch = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        return calendar.dateComponents([.day], from: epoch,
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// App Group suite the app and widget both use. Injected from the `APP_GROUP_ID` build setting
    /// (see project.yml) via the `AppGroupIdentifier` Info.plist key, so the value lives in exactly
    /// one place rather than being duplicated here. Must match the `com.apple.security.application-groups`
    /// entitlement on both targets (which also reads `$(APP_GROUP_ID)`). If the entitlement is missing on
    /// either side, `UserDefaults(suiteName:)` returns nil and every consumer (PendingIntents,
    /// WidgetSnapshot.publish, Live Activity) silently no-ops — see `assertGroupProvisioned` for the
    /// debug-time canary. The fallback is the canonical upstream group and only applies if the Info.plist
    /// key is somehow absent (each process reads its OWN bundle, so the app and the widget extension
    /// each carry the key in their generated Info.plist).
    public static let suiteName: String = {
        resolveSuiteName(infoDictionary: Bundle.main.infoDictionary ?? [:],
                         bundleIdentifier: Bundle.main.bundleIdentifier) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()
    public static let storageKey = "noop.widget.snapshot"

    /// Resolve the App Group the current signature actually grants.
    ///
    /// AltStore / SideStore must make every App Group unique to the user's signing team. During
    /// re-signing they append the team identifier to the group requested by the downloaded app and
    /// publish the resulting, provisioned identifiers in `ALTAppGroups` in each bundle's Info.plist.
    /// Reading only the build-time `AppGroupIdentifier` therefore points at an unprovisioned container
    /// in a sideloaded build, even though the host app and widget extension were both signed correctly.
    ///
    /// Normal Xcode builds don't carry `ALTAppGroups`, so they keep using `AppGroupIdentifier`.
    static func resolveSuiteName(infoDictionary: [String: Any]) -> String {
        let configured = (infoDictionary["AppGroupIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let altGroups = (infoDictionary["ALTAppGroups"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("group.") && !$0.isEmpty } ?? []

        if let configured, !configured.isEmpty,
           let provisioned = altGroups.first(where: {
               $0 == configured || $0.hasPrefix(configured + ".")
           }) {
            return provisioned
        }
        if altGroups.count == 1, let provisioned = altGroups.first {
            return provisioned
        }
        if let configured, !configured.isEmpty {
            return configured
        }
        return "group.com.noopapp.noop"
    }

    /// Every App Group this process might be entitled to, best guess first.
    ///
    /// The sideloader on the mini PC (AltKeeper / isideload) does not publish `ALTAppGroups` for NOOP. It
    /// creates `group.<signed main bundle id>` (the bundle id with the team id appended) and signs EVERY
    /// bundle with the main app's profile, so that is the only group the app, the widgets and the watch are
    /// actually entitled to. The build-time `AppGroupIdentifier` names a group that was never created, so the
    /// app and the widget each got a private, unshared store and the widget showed "Open NOOP to refresh".
    /// The extra candidates are the group named after this bundle and after the bundles above it (an
    /// extension drops its own suffix: `.widgets`, `.watch`, `.watch.complications`).
    ///
    /// Without a configured id (a bare host such as the unit tests) there is nothing to probe, so the list is
    /// just the existing answer.
    static func suiteNameCandidates(infoDictionary: [String: Any], bundleIdentifier: String?) -> [String] {
        let primary = resolveSuiteName(infoDictionary: infoDictionary)
        let configured = (infoDictionary["AppGroupIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty, let bundleIdentifier else { return [primary] }
        let parts = bundleIdentifier.split(separator: ".").map(String.init)
        var candidates = [primary]
        for dropped in 0...2 where parts.count - dropped >= 3 {
            let candidate = "group." + parts.dropLast(dropped).joined(separator: ".")
            if !candidates.contains(candidate) { candidates.append(candidate) }
        }
        return candidates
    }

    /// The first candidate the process can open a container for; the first candidate when none can (as before).
    static func resolveSuiteName(infoDictionary: [String: Any], bundleIdentifier: String?,
                                 hasContainer: (String) -> Bool) -> String {
        let candidates = suiteNameCandidates(infoDictionary: infoDictionary, bundleIdentifier: bundleIdentifier)
        if candidates.count == 1 { return candidates[0] }
        return candidates.first(where: hasContainer) ?? candidates[0]
    }

    /// Debug-only canary: trips on the first run after a misprovisioning so the silent no-op gets
    /// caught immediately rather than masquerading as "widget shows nothing yet." Release builds do
    /// nothing — App Store apps can't crash on a missing entitlement.
    public static func assertGroupProvisioned() {
        assert(UserDefaults(suiteName: suiteName) != nil,
               "App Group '\(suiteName)' not provisioned on this target — check the entitlement.")
    }

    public static var placeholder: WidgetSnapshot {
        // Gallery / pre-publish stand-in: realistic Charge · Effort · Rest on the 0–100 axis so the
        // three-ring Home Screen layouts (and the large grid) preview with filled arcs, not dashes.
        WidgetSnapshot(recovery: 72, bpm: 58, batteryPct: 84, bonded: true, updated: Date(),
                       effort: 38, rest: 81, hrv: 64, restingHr: 52,
                       effortDisplay: "38", effortWhoop: false)
    }

    /// Honest runtime state when the app has not published a readable snapshot yet. Unlike
    /// `placeholder`, this is user-visible and must never imply that sample data is real.
    static var unavailable: WidgetSnapshot {
        WidgetSnapshot(recovery: nil, bpm: nil, batteryPct: nil, bonded: false, updated: .distantPast)
    }

    /// Read the last-published snapshot from the shared suite, if any.
    public static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: storageKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        return snap
    }

    /// Persist this snapshot into the shared suite, folding the live bpm into the trace on the way.
    ///
    /// The fold happens HERE, not in the callers that build a snapshot, so nothing that publishes has to
    /// know the retention rule — the twin of the Android store owning it. A snapshot with no bpm leaves
    /// the stored trace alone rather than truncating it, so a quiet strap does not erase the history the
    /// widget is drawing.
    public func save() {
        save(previousSeries: WidgetSnapshot.load()?.hrSeries ?? [])
    }

    /// As `save()`, for a caller that already holds the stored snapshot.
    ///
    /// The publish path loads `previous` to decide whether anything changed, and `save()` was then
    /// decoding the same App Group blob a second time just to reach the trace. Handing the series in
    /// costs the caller nothing and removes a full JSON decode from every publish.
    public func save(previousSeries: [HrPoint]) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName) else { return }
        var toStore = self
        let previous = previousSeries
        let nowSec = Int64(updated.timeIntervalSince1970)
        toStore.hrSeries = bpm.map { HrTrace.append(previous, ts: nowSec, bpm: $0, nowSec: nowSec) }
            ?? HrTrace.prune(previous, nowSec: nowSec)
        guard let data = try? JSONEncoder().encode(toStore) else { return }
        defaults.set(data, forKey: WidgetSnapshot.storageKey)
    }

    /// Does the TRACE need a point, even though nothing the header renders has changed?
    ///
    /// `renderedContentChanged` compares bpm, not history, so a steady heart — the ordinary case at rest
    /// — produced no publish and therefore no new trace point. The trace would stop advancing while the
    /// strap streamed happily, and pruning would eventually empty it. Android does not have this problem
    /// because its PushGate re-admits an unchanged key once a minute; this is that rule.
    ///
    /// Keyed on the BUCKET rather than elapsed seconds, so it asks for a write exactly when
    /// `HrTrace.append` would actually record one, and never more often.
    static func traceNeedsPoint(previous: WidgetSnapshot?, bpm: Int?, now: Date) -> Bool {
        guard let bpm, bpm > 0 else { return false }
        guard let last = previous?.hrSeries?.last else { return true }
        return Int64(now.timeIntervalSince1970) / HrTrace.bucketSec > last.ts / HrTrace.bucketSec
    }

    /// Whether publishing `next` would change anything the widget actually renders. `updated` is
    /// deliberately excluded: no widget family displays it, and treating a fresh timestamp as content
    /// would defeat deduplication because every otherwise-identical build creates a new date.
    ///
    /// Shared by the full score publish and the live-only fast path so a redundant foreground, repository,
    /// battery, or connection signal does not rewrite App-Group defaults and ask WidgetKit to rebuild an
    /// identical timeline. nil means the app has never published, so the first snapshot always writes.
    static func renderedContentChanged(from previous: WidgetSnapshot?, to next: WidgetSnapshot) -> Bool {
        guard let previous else { return true }
        return previous.recovery != next.recovery
            || previous.bpm != next.bpm
            || previous.batteryPct != next.batteryPct
            || previous.bonded != next.bonded
            || previous.effort != next.effort
            || previous.rest != next.rest
            || previous.hrv != next.hrv
            || previous.restingHr != next.restingHr
            || previous.effortDisplay != next.effortDisplay
            || previous.effortWhoop != next.effortWhoop
            // The curve joins the comparison (#2040): a publish that scored a fresh hour and changed
            // nothing else would otherwise be deduped away, and the widget would sit an hour behind
            // until some unrelated field moved. The DAY joins it too, so the first publish after
            // midnight still reaches WidgetKit even when the new day has no scored hour yet.
            || previous.stressSeries != next.stressSeries
            || previous.stressDay != next.stressDay
            // The Effort target: its figures and day, plus the hour it was written in. The stamp is the
            // widget's freshness check, so an otherwise-identical publish must still refresh it, but only
            // once an hour rather than on every publish.
            || previous.effortTargetEffort != next.effortTargetEffort
            || previous.effortTargetEffortText != next.effortTargetEffortText
            || previous.effortBandLow != next.effortBandLow
            || previous.effortBandHigh != next.effortBandHigh
            || previous.effortBandText != next.effortBandText
            || previous.effortToGo != next.effortToGo
            || previous.effortTargetDay != next.effortTargetDay
            || previous.scoresHidden != next.scoresHidden
            || previous.bodyHidden != next.bodyHidden
            || effortTargetHour(previous.effortTargetAt) != effortTargetHour(next.effortTargetAt)
    }

    private static func effortTargetHour(_ date: Date?) -> Int? {
        date.map { Int($0.timeIntervalSince1970 / 3_600) }
    }

    /// A live-only update may reuse score fields only within the same local calendar day. At rollover,
    /// the full publisher must resolve `Repository.widgetAnchor` again so yesterday's Charge/Rest cannot
    /// be carried forward indefinitely by a stream of HR updates. Calendar is injectable for deterministic
    /// tests; production uses the user's current calendar and time zone.
    static func liveUpdateRequiresFullBuild(previous: WidgetSnapshot?, now: Date,
                                            calendar: Calendar = .current) -> Bool {
        guard let previous else { return true }
        return !calendar.isDate(previous.updated, inSameDayAs: now)
    }
}
